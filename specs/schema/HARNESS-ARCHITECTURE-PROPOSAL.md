# Verity Harness — Architecture (detailed design)

**Status:** Accepted — design of record for the harness runtime.
**Decision record:** [[0010-harness-runtime-federated-coordinator]] (the ADR fixes the
architecture; this document carries the operational detail it defers to).
**Boundary invariants:** [[0002-execution-model]] (app-hosted), [[0003-harness-governance-api]]
(API-only), [[0006-packages-and-governed-deployment]] (governed deployment),
[[0005-schema-hardening]] (three schemas, reference-vocab status).

> This document was reconciled to the **as-built** schema. Three points differ from the
> first draft and are authoritative here: (a) **all status fields are reference vocab
> tables**, not native enums; (b) the **coordinator is the cluster's sole hub uplink**
> (workers do not call the hub directly); (c) on k8s the **operator and coordinator are
> separate** components (least privilege), merging only on bare Linux. See §10.

---

## 1. Shape

The harness is hub-and-spoke. The **hub** is Verity (Gateway API + verity-relay + NATS +
Postgres + object store). Each **spoke** is a customer cluster running an **operator**
(lifecycle), an elected **coordinator** (dispatch leader), and **N workers** (executors).

```
APP CLUSTER (spoke)                         VERITY (hub)
  operator  ── reconciles ──┐                 Harness Gateway API  ← only DB gateway
  coordinator ── sole uplink ── TLS 443 out ─→ verity-relay        → drains outboxes to NATS
  workers   ── via coordinator ┘               NATS JetStream      ← work + commands + events
                                               PostgreSQL (ref/core/audit)
                                               object store (.vtx/.vax, artifact pulls)
```

**API-only is absolute.** The spoke holds no DB credential. Every SQL statement runs
hub-side inside a Gateway API handler. The coordinator makes outbound HTTPS calls only.

## 2. Components in the harness image

- **Execution engine** — the agentic loop variant (`reference.harness_variant`).
- **Package loader + integrity verifier** — pulls `.vtx/.vax`, checks the SHA-256 manifest
  before any data is touched.
- **Binding resolvers** — Source/Target bindings against storage connectors, honoring
  delivery mode and run-mode suppression (shadow).
- **NATS client** — consume work/commands, publish events + heartbeats.
- **Gateway API client** — carries the cluster mTLS identity; claims, state writes, log
  ingest, heartbeats, command acks.
- **Local SQLite cache** — lease record, in-flight job copies, quota cache, artifact
  manifest (operational cache only; the hub is authoritative).
- **Control agent** — register, heartbeat, execute portal commands.
- **Master-only:** coordinator leadership + the cluster's single hub uplink.

**There is no Postgres inside the harness.** The durable queue is central NATS; the system
of record is central Postgres behind the Gateway; SQLite is a thin local cache.

## 3. Decision record (Q-1 … Q-6)

**Q-1 Leadership — heartbeat lease (`core.harness_coordinator`).** One row per cluster.
The Gateway runs, on each coordinator heartbeat, the atomic
`UPDATE … SET lease_expires_at = now()+lease WHERE cluster=$c AND (holder=$n OR lease_expires_at < now())`
and returns `lease_held = row_count>0`. Row locking serialises competitors → no
split-brain. No advisory locks (need a spoke DB connection — forbidden — and a partition
watchdog). No NATS KV (extra dependency on every cluster). `lease = 3×heartbeat` (6 min
default; tunable per cluster). Single-node clusters skip election (always coordinator) but
still write the row for observability.

**Q-2 Work queue — `core.harness_dispatch`.** A materialised, mutable per-run dispatch row
the coordinator polls (via the Gateway), separate from `execution_run_current` (a
`DISTINCT ON` view that cannot serve "next N by priority" efficiently). Written in **one
transaction** with the append-only `execution_run_status`. `write_idempotency_key` =
`run_id || '-a' || attempt_number` (STORED) changes on every requeue; target connectors
dedupe on it.

**Q-3 App credentials — Model B (spoke-local, hub metadata only).** `core.harness_app_credential`
holds name/type/verification only — no value, no vault ref. Secrets live on the spoke (k8s
Secret via ESO; encrypted file on Linux; env file in dev only). The coordinator
test-connects and reports `credential_verification_status`. V2 may add direct customer
vault integration; the hub model is unchanged.

**Q-4 Node roster — `core.harness_node`.** Models the coordinator-eligible host (pod in
k8s, VM on Linux), distinct from `harness_instance` (the container). `is_coordinator_active`
mirrors `harness_coordinator` for the dashboard (observability only).

**Q-5 Command delivery — `core.harness_command_outbox`.** Separate from
`run_dispatch_outbox`: commands route to a cluster (not a run), carry a 24h TTL, and use
`acknowledged`/`expired` states. Same pattern: write in one txn with
`harness_instance_command` → verity-relay publishes to `verity.cluster.{id}.commands` →
coordinator acks via the Gateway.

**Q-6 Automation actor granularity — one per cluster.** `automation_actor.deployment_cluster_id`
(soft ref) — one machine principal per cluster, not per instance, to avoid actor
proliferation from pod churn. Operational host identity is carried on
`execution_run_status.worker_node_id`.

## 4. Enhancements

**E-1 Coordinator-local SQLite.** Four jobs: lease record (re-election on restart),
island-mode in-flight job state (reconcile on reconnect), quota cache (soft/hard
enforcement while disconnected), artifact-cache manifest (SHA-256 verify with no hub call).
Not replicated, not a message queue, wiped on decommission. k8s: emptyDir (hub is
authoritative). Linux: `/var/lib/verity-harness/coordinator.db`.

**E-2 Circuit breaker → island mode.** Open after N=5 consecutive Gateway failures.
Backoff 30→60→120→240→300s (cap). OPEN: executing jobs continue (model API direct, local
cache); events buffer in cluster-local NATS JetStream (≤10k/24h); new dispatch pauses;
quota enforced from SQLite; the lease stops refreshing (a reachable node can take over —
correct). HALF-OPEN probe succeeds → replay buffer, reconcile dispatch, refresh quota,
resume.

**E-3 Credentials — Model B.** As Q-3.

## 5. Heartbeat

- **Minor** (every 2 min, coordinator only): lease refresh + liveness. The Gateway runs the
  lease UPDATE and returns `lease_held`; if false the coordinator steps down. Also updates
  `harness_node.last_heartbeat_at`, `harness_instance.last_seen`, inserts
  `audit.harness_heartbeat (minor)`.
- **Major** (hourly + event-driven): adds the running-package catalog (`running_packages`
  JSONB) → `audit.harness_running_package_current` → drift vs. `core.deployment`.
  Event triggers: package deploy ack, new election, portal `collect_diagnostics`, local
  drift detected.
- **Volume at 1000 clusters, 7-day retention:** ~1 GB minor + ~0.5 GB major ≈ 1.5 GB.
  Daily partitions, drop > 7 days, export to external analytics ([[0007-decision-log-scale-and-portable-analytics]]).
- **Health mapping:** 0–4 min healthy; 4–6 min amber (2 missed); > 6 min lease expired →
  unhealthy / island / failover. The 3× multiplier tolerates two missed beats so transient
  blips don't trigger failover.

## 6. Failure scenarios (summary)

| # | Scenario | Outcome |
|---|---|---|
| 1 | 3 nodes start together | One INSERT wins; two get 0-row UPDATE → standby. Exactly one coordinator. |
| 2 | Coordinator clean shutdown | Lease stops refreshing; standby wins after expiry (0–6 min, ~3 avg). In-flight uninterrupted. |
| 3 | Coordinator crash (kill -9/OOM) | Same as clean — lease is time-based. New coordinator requeues only dead workers' jobs. |
| 4 | Machine hard reboot | Identical to crash — no TCP-keepalive dependency (the advisage over advisory locks). |
| 5 | Partition: A can't reach hub, B can | A's lease expires; B (reachable) wins. A islands, rejoins as standby on heal. |
| 6 | Hub Postgres down | All island; no election possible (nobody can UPDATE) → no split-brain. Clean re-election on recovery. |
| 7 | Gateway down, Postgres up | All island; first to reconnect wins (or A keeps lease if < 6 min). |
| 8 | Two standbys claim same instant | Row lock serialises; one UPDATE wins, one gets 0 rows. Split-brain impossible. |
| 9 | 1000 clusters sustained | 8.3 minor writes/s, 200 standby-poll reads/s, 50 pooled connections (transaction mode). No bottleneck. |
| 10 | Hub load spike, slow UPDATE | 2-min interval + N=5 threshold damps transient load; no spurious failover. |

## 7. Dispatch & deployment

**Submission:** Gateway writes `execution_run` + `harness_dispatch (queued)` +
`run_dispatch_outbox (pending)` (+ a `quota_check`) in one txn → verity-relay publishes
`verity.runs.pending` → coordinator claims via Gateway (`claimed`/`assigned`) → worker
executes (`executing`) → releases (`released`); the worker reports **through the
coordinator** (sole uplink), which writes `execution_run_status` + `harness_dispatch` (one
txn) + `audit.decision_log`.

**Package deploy (`deploy_package`, coordinator):** download bundle → verify SHA-256 →
store alongside old in cache → update SQLite manifest → set active → ack → Gateway flips
`deployment.deployment_status_code` (new `active`, old `superseded`). Bundles load **once
at claim time**, so in-flight jobs finish on their original bundle; **no drain**.

**Image deploy (`patch`, operator):** a Deployment roll. The portal surfaces **graceful**
(drain: stop new dispatch, finish in-flight to timeout, then restart) vs. **force**
(restart now; in-flight requeued with a new `write_idempotency_key`). The graceful/force
choice appears on `patch`, never on `deploy_package`.

## 8. Security & enrollment

- **Bootstrap:** portal mints a one-time, short-lived enrollment token; operator/agent
  installed with it; spoke exchanges it for an **mTLS cert + app-scoped API key** (token
  consumed). Outbound-only TLS 1.3 on 443; zero inbound ports; proxy-friendly.
- **Ongoing:** mTLS (cluster cert, auto-rotated on a 7-day overlap via `patch_cert`) +
  short-lived JWT refreshed by the coordinator.
- **Credential security:** k8s via ESO → Secret → pod; Linux via encrypted file →
  in-memory at startup. Never logged, never sent to the model, never in decision logs. The
  hub holds name/type/verification only.

## 9. Scale (write load behind the Gateway)

| Operation | 100 clusters | 500 | 1000 |
|---|---|---|---|
| Minor heartbeat writes | 0.83/s | 4.2/s | 8.3/s |
| Major heartbeat writes | 0.03/s | 0.14/s | 0.28/s |
| Standby lease polls | 20/s | 100/s | 200/s |
| Pooled Postgres connections (txn mode) | 10 | 30 | 50 |
| `audit.harness_heartbeat` (7-day) | 150 MB | 0.75 GB | 1.5 GB |

`harness_dispatch` is bounded by active jobs (not cumulative); `harness_coordinator` is one
row per cluster. No bottleneck identified to 1000 clusters.

## 10. As-built reconciliation (authoritative)

- **Status fields are reference vocab tables**, per [[0005-schema-hardening]] (universal;
  supersedes the D1 native-enum exception). New: `reference.run_dispatch_status`,
  `command_outbox_status`, `harness_node_status`, `credential_verification_status`.
  Converted: `outbox_status`, `run_status`, `run_completion_status`.
- **Coordinator-only egress.** Workers reach the hub solely through the coordinator; the
  cluster has one mTLS identity. In-flight execution never depends on the coordinator.
- **Operator ≠ coordinator on k8s.** The operator (k8s RBAC, lifecycle) is the only
  privileged component and never touches customer data/the model; the coordinator/workers
  hold no k8s API access. They merge into one local agent only on bare Linux.
- **Directional naming.** Every table in the chain opens its comment with `LEG:` and names
  the acting party in transition columns (`published_to_cluster_at`,
  `claimed_by_coordinator_at`, `assigned_to_instance_id`, `worker_started_at`, …).
- **Schema delta:** 5 new `core` tables (`harness_node`, `harness_coordinator`,
  `harness_dispatch`, `harness_app_credential`, `harness_command_outbox`); 2 new columns
  (`automation_actor.deployment_cluster_id`, `execution_run_status.worker_node_id`); 2 new
  command kinds (`deploy_package`, `patch_cert`). No new top-level schema (D3 holds).
