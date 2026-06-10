# ADR-0015 — Message broker, dispatch pipeline, application invocation protocol, and log artifact storage

- **Status:** Accepted
- **Date:** 2026-06-09
- **Deciders:** Product Owner (Anil)
- **Related:** [[0002-execution-model]], [[0003-harness-governance-api]],
  [[0004-storage-architecture]], [[0007-decision-log-scale-and-portable-analytics]],
  [[0010-harness-runtime-federated-coordinator]], [[0011-repository-topology-and-harness-release-boundary]]

---

## Context

[[0010-harness-runtime-federated-coordinator]] fixed the coordinator/worker topology, the
heartbeat lease election, island mode, and enrollment. It named NATS JetStream and the
transactional outbox as the dispatch mechanism, and CloudNativePG as the HA database, but
left several concrete questions to the component spec:

1. **Job queue**: how does a run submitted to the hub reach the coordinator — polling or
   message broker? If broker, which one? What are the durability and resilience properties?
2. **Execution status**: how does the application get the status and result of a run it
   submitted? Polling? SSE? Webhook?
3. **Heartbeat and master management**: implicit in [[0010]], but the error-detection
   consequence for hard harness failures was not specified.
4. **Decision logs and log artifacts**: how do large per-run files (decision log, execution
   events, technical logs) reach durable storage without proxying through the hub?
   What is the object store? What are the retention tiers?
5. **Technical operational logs**: who owns harness stdout/stderr, and how is it accessed?

This ADR closes all five. It also resolves the open decisions from the PCR for **message
broker** (§1), **Postgres HA provider** (§4), and **artifact object store** (§5).

---

## Decision

### 1. NATS JetStream is the job dispatch broker

**NATS JetStream** is the message broker for run dispatch. Work flows as follows:

```
governance API  →  run_dispatch_outbox (Postgres, Tier-1)
                →  verity-relay (background publisher, drains outbox → NATS)
                →  NATS JetStream subject: verity.runs.pending
                →  coordinator (durable consumer, calls Hub Gateway to claim)
                →  worker (executes — no hub in the hot path)
```

The **transactional outbox pattern** (already fixed in [[0010]]) is the durability
guarantee: the governance API writes `execution_run`, `harness_dispatch` (state `queued`),
and `run_dispatch_outbox` (state `pending`) in one Postgres transaction. `verity-relay` is
a background publisher that drains the outbox to NATS at ~60s CronJob sweep cadence. If
NATS is unavailable at publish time, the outbox row stays `pending` and the sweep retries.
No run is lost between Postgres commit and NATS delivery.

The coordinator subscribes to `verity.runs.pending` with a durable consumer group. On
receipt it calls the Harness Gateway API to claim the run — this is a Postgres
`UPDATE … WHERE lease_expires_at < now() OR coordinator_node_id = $node` transaction
(the same atomic-update pattern as the heartbeat lease). The claim confirms the run is
assigned to this cluster.

Workers receive work exclusively from the coordinator via **cluster-local NATS**. Workers
hold no hub credential and make no direct hub calls. The coordinator is the cluster's
sole hub uplink ([[0010]] §4).

**Island mode**: when the hub is unreachable the coordinator's circuit breaker opens.
In-flight jobs continue; cluster-local NATS buffers new execution events (bounded
10 k / 24 h); new dispatch pauses (the coordinator cannot claim without the hub). On
reconnect the coordinator replays the buffer and reconciles.

### 2. Applications invoke via the hub; poll for status and result

Applications never contact the harness directly. The complete invocation contract is:

```
POST  /api/v1/runs          →  { run_id, status: "queued" }

GET   /api/v1/runs/{run_id} →  { run_id, status: "executing" }   (poll until terminal)
GET   /api/v1/runs/{run_id} →  { run_id, status: "completed",
                                  output: "...",
                                  decision_log_id: "...",
                                  log_url: null }
GET   /api/v1/runs/{run_id} →  { run_id, status: "failed",
                                  error: { code, message, occurred_at },
                                  log_url: "<pre-signed URL or null>",
                                  decision_log_id: "<partial record id or null>" }
```

**Polling is the only application-facing status mechanism.** Webhooks and SSE are not
offered to applications. Polling is stateless, works from any HTTP client, requires no
persistent connection management, and is sufficient for the 1–5 s job profile. The
`execution_run_current` view (Tier-1 Postgres) is the read target; it is kept current
by the coordinator's batched status relay to the Hub Gateway (~200 ms batch intervals).

**Result is inline** on the `completed` response. The application does not need a
separate result fetch for normal operation. The `decision_log_id` is always returned;
the full structured audit record is at `GET /api/v1/decisions/{decision_log_id}` for
governance and compliance consumers.

**SSE** is used only as the coordinator → hub internal event relay: the coordinator
batches execution events (turn_started, tool_called, claude_responded, etc.) and pushes
them to the Hub Gateway. This is hub-internal infrastructure; it is not exposed to
applications.

### 3. Hard failure detection is hub-side, not harness-side

`error.json` (a structured error artifact written by the worker) is a **best-effort
artifact for graceful failures only** — caught exceptions, handled shutdown. It does not
and cannot exist for hard failures (OOM kill, node loss, kernel panic).

Hard failure detection is the hub's responsibility:

- **Worker lost**: coordinator detects via missed worker heartbeat → marks assignment lost
  → reports `job_lost` to Hub Gateway → hub writes `harness_dispatch` as `failed` with
  `error_code = worker_lost`.
- **Coordinator lost**: hub detects via lease expiry (`lease_expires_at < now()`) →
  marks all `executing` dispatch records for that cluster as `failed` with
  `error_code = coordinator_timeout`.

In both cases the application's next poll returns `status: failed, log_url: null`. There
is no file artifact because the harness wrote nothing. Operational diagnosis of hard
failures uses the k8s log aggregator (§5), not the governance platform.

Even failed runs produce a `decision_log_id` if at least some execution events were
relayed to the hub before failure; the partial record is marked `partial: true`.

### 4. CloudNativePG is the Postgres HA solution for the hub platform

**CloudNativePG** (primary + read replica + PITR, minimum 7-day retention) is the
reference implementation for the governance database on the hub platform. The governance
API writes to the primary; read-heavy queries (run status, `execution_run_current`) use
the read replica. AWS RDS Multi-AZ, GCP AlloyDB, and Azure Database for PostgreSQL are
acceptable substitutes for cloud-managed deployments; CloudNativePG is used in the
reference IaC ([[0017-deployment-substrate-kubernetes-environment]]).

### 5. MinIO is the object store; log artifacts upload via pre-signed URLs

**MinIO** is the reference object store for both the Tier-2 analytics log store
([[0004-storage-architecture]], [[0007-decision-log-scale-and-portable-analytics]]) and
for per-run log artifacts. AWS S3, GCS, and Azure Blob are acceptable cloud substitutes;
all use the S3-compatible API that MinIO exposes.

The harness never holds a long-lived object store credential. The upload flow is:

1. Worker requests a **pre-signed PUT URL** from the Hub Gateway API at run start.
2. Hub generates the URL (scoped to `{tenant_id}/runs/{yyyy}/{mm}/{dd}/{run_id}/`),
   valid for a short window (1 h), and returns it. The credential stays hub-side.
3. Worker uploads files **directly to object storage** using the pre-signed URL —
   no bytes proxy through the hub.
4. Worker includes `log_path` and `decision_log_id` in the `release` call to the
   Hub Gateway.
5. Hub stores `log_path` in `execution_run`. Pre-signed **download** URLs are generated
   on demand when an application calls `GET /runs/{run_id}` and a `log_url` is needed.

This satisfies [[0003-harness-governance-api]]'s API-only boundary: the harness negotiates
every storage interaction through the Gateway API but transfers bytes directly.

#### Per-run artifact layout

```
{tenant_id}/runs/{yyyy}/{mm}/{dd}/{run_id}/
  decision_log.json        — governance record (JSON, nested — see §6)
  model_invocations.jsonl  — one JSON object per line, per API call/turn
  execution_events.jsonl   — all execution events in order (coordinator-buffered)
  error.json               — graceful failure only; absent on hard failure
```

Date partitioning enables retention lifecycle policies by prefix. `error.json` is absent
on hard failure; `log_url: null` in the poll response signals this to the application.

#### Log retention tiers

| Artifact | Retention | Rationale |
|---|---|---|
| `decision_log.json` | Indefinite | Compliance record |
| `model_invocations.jsonl` | Indefinite | Compliance / cost audit |
| `execution_events.jsonl` | 90 days | Operational debugging |
| `error.json` | 90 days | Operational debugging |

Object store lifecycle policies enforce expiry automatically by `runs/{yyyy}/{mm}/{dd}/`
prefix.

### 6. Decision log is JSON with nested structure; model invocations are JSONL

The per-run **decision log is JSON** (one file per run, not Parquet). The V1
`agent_decision_log` table design is the reference: flat scalar fields alongside several
nested JSONB columns (`inference_config_snapshot`, `input_json`, `output_json`,
`message_history`, `tool_calls_made`, `source_resolutions`, `target_writes`). V2
serialises this structure to `decision_log.json` using the same shape.

`message_history` is deeply nested: an array of messages, each with a `content` array
that can hold text blocks, tool_use blocks, and tool_result blocks. This structure cannot
be represented flat without semantic loss. JSON is the correct format.

`model_invocations.jsonl` is JSONL (one JSON object per line). Newlines within string
fields (reasoning text, tool output) are escaped as `\n` by the JSON serialiser — this
is standard JSON serialisation behaviour and requires no special handling.

The **Tier-2 Iceberg/Parquet columnar store** ([[0004-storage-architecture]]) is an ETL
projection built asynchronously by a pipeline that reads these JSON files. Parquet is
the analytics read format; it is never the per-run write format. The harness is unaware
of the ETL pipeline.

### 7. Technical operational logs are the infrastructure team's concern

Harness `stdout`/`stderr` — Python log lines, library warnings, timing output, full
stack traces — are **not a governance platform artifact**. On Kubernetes they go to pod
stdout and are collected by the app team's log aggregator (Loki, Fluentd, Datadog, or
equivalent). The governance platform stores no reference to them and generates no
pre-signed URL. The app team accesses them via their own log stack.

On bare Linux the equivalent is journald or a log file with rotation, managed by the app
team's operational tooling.

This boundary is deliberate: technical logs have short retention, high volume, and
operational audience. Mixing them into the governance platform's object store would
conflate operational and compliance artifacts.

---

## Consequences

**Positive**
- NATS JetStream + transactional outbox means no run is ever lost between Postgres commit
  and NATS delivery; the relay's sweep is the backstop.
- The hub is not in the execution hot path: LLM calls, tool calls, and connector I/O all
  happen in the worker without a hub hop.
- Simple, stateless application polling removes all persistent-connection management from
  the application side.
- Pre-signed URL upload keeps large artifact bytes off the hub while preserving the
  API-only boundary.
- Hard failure detection via heartbeat timeout gives the hub a clean signal without
  requiring the harness to report its own death.
- Date-partitioned log layout makes object store lifecycle policies trivial.

**Negative / costs**
- `verity-relay` is a new process to operate. Its 60 s sweep is the recovery window for
  a failed NATS publish; run dispatch is not real-time during a relay outage.
- Island mode buffers events but pauses new dispatch; applications submitting runs during
  a hub outage will queue indefinitely unless the hub recovers.
- `log_url: null` on hard failure is the correct contract, but applications must handle
  the absence of log artifacts gracefully.
- The ETL pipeline (JSON → Parquet Tier-2) is a separate piece of infrastructure to build
  and operate (deferred to Phase 9 per roadmap).

## Alternatives considered

**Postgres `SKIP LOCKED` polling instead of NATS (v1 model).** Would eliminate the broker
entirely. *Rejected as the primary path* for scale: a polling loop on `harness_dispatch`
means every coordinator in every cluster is hitting the governance database on a timer.
At hundreds of clusters this is a significant read load on the system-of-record database.
NATS fans work out to coordinators without polling. The outbox/relay keeps Postgres as the
durable source and NATS as the fast delivery layer. `SKIP LOCKED` polling remains viable
as a `VERITY_DISPATCH_MODE=postgres` fallback feature flag for environments where NATS
is unavailable.

**Redis Streams as the broker.** Capable, lower operational overhead than NATS for simple
queue-style workloads. *Rejected*: Redis is not already in the stack; NATS JetStream is
already referenced in [[0010]] for cluster-local buffering (island mode), so using it for
the hub→cluster dispatch too means one broker technology, not two. Redis adds a dependency
without adding a capability we don't already have from NATS.

**AWS SQS / cloud-native broker.** Would tie the hub platform to a specific cloud.
*Rejected* — the platform targets CNCF-portable infrastructure ([[0017]]).

**SSE or webhooks for application status.** SSE requires the hub to maintain one
long-lived connection per active run subscriber — a different scaling profile (connection
count rather than request rate) that adds operational complexity. Webhooks require
applications to expose inbound endpoints (firewall rules, TLS cert management,
authentication of the incoming call). Both are richer than needed for the 1–5 s job
profile. *Polling is sufficient* and the simpler contract.

**Hub proxying log uploads.** Would route all artifact bytes through the governance API.
*Rejected* — adds unnecessary load on the hub for large files; pre-signed URLs achieve
the same result (API-only boundary) without the proxy cost.

**Long-lived object store credentials in the harness.** Would simplify the upload path
(no pre-signed URL negotiation). *Rejected* — contradicts [[0003-harness-governance-api]]
(API-only, no long-lived credentials outside the hub) and the enrollment/credential model
in [[0010]].

## Notes

The `verity.runs.pending`, `verity.cluster.{id}.commands`, `verity.events.{run_id}`, and
heartbeat NATS subject schemas, plus the Harness Gateway API OpenAPI spec for
claim/release/heartbeat/ack and the pre-signed URL endpoints, are specified in
`contract/` ([[0011-repository-topology-and-harness-release-boundary]] §2). This ADR
fixes the architecture; the `contract/` component spec carries the wire format.
