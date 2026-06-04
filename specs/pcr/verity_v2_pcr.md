# Verity v2.0 — Product Change Request

**Document type:** Product Change Request (PCR)  
**Status:** DRAFT — Pending architectural review  
**Version:** 0.2  
**Date:** May 2026  
**Legacy reference:** Verity v1 — Docker Compose demo stack

---

## Purpose

This PCR authorises the discontinuation of the existing Verity v1 Docker Compose monolith as the primary development target and establishes the architecture, methodology, and scope for a ground-up rebuild — Verity v2 — designed for horizontal scalability, containerised distributed execution, and 100% specification-driven development from day one.

---

## Rebuild vs. Modify — Decision

### Why not modify v1

The v1 codebase is architecturally clean for what it is. The schema, raw SQL query files, Pydantic models, async psycopg v3, the SKIP LOCKED worker, and the event-sourced run tracking are all correct and well-designed. The 78-operation API surface works.

However, three factors make modification the wrong choice:

**1. Spec-first is impossible to retrofit.** The primary requirement for v2 is 100% specification-driven development — spec precedes implementation, always. Writing specs to match existing code is documentation, not specification. The discipline only works from an empty repository.

**2. Docker Compose assumptions are structural.** The v1 codebase was built with single-process assumptions throughout: shared `Verity` coordinator, shared `Database` pool, governance and runtime in the same Python process. The K8s migration plan describes how to untangle this, but every touched file has to be audited for shared-process assumptions. Starting clean is faster and safer.

**3. The artifact system changes fundamental flows.** The `.vtx`/`.vax` packaging, integrity check protocol, and owned container deployment model are not additions — they change how champion promotion works, how the worker claims runs, and how entity configuration reaches the execution environment. These changes touch the shape of existing core flows throughout the codebase.

### What is carried forward (as reference, not as code)

| Artefact | Treatment in v2 |
|---|---|
| `schema.sql` | Copied directly as `specs/schema/verity_schema.sql` — the canonical DB spec |
| SQL query files (`registry.sql`, `runs.sql`, etc.) | Reference for writing v2 query specs; not copied into implementation |
| API surface (78 ops, 54 paths) | Documented as input to Phase 0 OpenAPI 3.1 spec; not copied as route handlers |
| Product vision and design principles | Carried forward unchanged |
| All governance documentation | Carried forward as Phase 0 spec inputs |

### What is not carried forward

- Python source code
- Docker Compose configuration
- Dockerfiles
- Seed scripts
- Test fixtures

**v1 is archived as the legacy reference implementation. v2 is a new repository.**

---

## 1. What is Preserved from v1

The following are carried forward into v2 without redesign. v1 is the reference.

- Complete governance metamodel and PostgreSQL schema (43 governance tables, 8 runtime tables, all enumerations and views)
- 6-state lifecycle: `draft → candidate → staging → challenger → champion → deprecated` (v1's `shadow` is now a **challenger run-mode**, not a state; `deprecated` is restorable via rollback)
- Immutable decision log (`agent_decision_log`) as the canonical audit record
- Event-sourced run tracking (`execution_run`, `execution_run_status`, `execution_run_completion`, `execution_run_error`, `execution_run_current` view)
- Entity model: agents, tasks, prompts, tools, inference configs, data connectors, MCP servers
- Declarative I/O grammar: `source_binding`, `write_target`, `target_payload_field`
- Champion resolution, SCD-2 temporal versioning, pgvector similarity checking
- Compliance primitives: model cards, validation runs, ground truth datasets, approval records, quotas
- Product vision: governance infrastructure that AI applications run on, not an AI application itself
- Regulatory targets: SR 11-7, NAIC, CO SB21-169, NIST RMF, ISO 42001

---

## 2. What Changes

| Layer | v1 | v2 |
|---|---|---|
| Deployment substrate | Docker Compose monolith | Kubernetes-native, Helm chart, horizontally scalable |
| Execution model | In-process Python SDK | Containerised distributed runtime, `.vtx`/`.vax` artifact bundles |
| Dispatch layer | Postgres poll loop | NATS JetStream transactional outbox |
| Event streaming | Unwired `ExecutionEvent` contract | NATS per-run subjects + SSE bridge, wired from day one |
| Postgres availability | Single instance | HA primary/replica + PITR (CloudNativePG or managed) |
| Development methodology | Iterative enhancement | 100% spec-driven — spec precedes all implementation |
| Authentication | None | API keys + sessions (OIDC optional) |
| Secrets | Hardcoded in `docker-compose.yml` | Kubernetes Secrets, no hardcoded credentials anywhere |
| Observability | Container logs only | Prometheus metrics, OpenTelemetry traces, Grafana dashboards |

---

## 3. Architecture Pivots

### 3.1 Kubernetes-native deployment from day one

Verity v2 targets Kubernetes as its primary deployment substrate. A Helm chart is the primary delivery artefact. Docker Compose is retained only as a local development convenience and is never the source of truth for service configuration.

**Services:**

| Service | Role | Scaling |
|---|---|---|
| `verity-governance` | Governance API, admin UI, lifecycle engine | Stateless — horizontal replicas + load balancer |
| `verity-runtime` | Execution worker fleet | Stateless — HPA on NATS queue depth |
| `verity-vault` | Document store service | Stateless — scaled independently |
| `postgres-governance` | CloudNativePG HA cluster | Primary + read replica + PITR |
| `postgres-vault` | Separate Postgres cluster for vault | Primary + read replica |
| `nats` | JetStream event and dispatch broker | 3-replica cluster, PVC-backed |
| `minio` | Object store for artifact bundles and documents | StatefulSet |

**Design constraint:** No service may hold shared in-process state with another service. Each service boundary is enforced at the network level via NetworkPolicies.

---

### 3.2 `.vtx` / `.vax` execution artifact format

Every agent or task that reaches `champion` state is packaged into a signed, self-describing deployment artifact at the moment of promotion. Tasks produce `.vtx` files; agents produce `.vax` files. Both are ZIP archives renamed with the Verity extension.

**Bundle contents:**

| File | Purpose |
|---|---|
| `manifest.json` | SHA-256 hash of every other file in the bundle. The integrity anchor. |
| `registry_ref.json` | `entity_name`, `version_id`, `champion_since`, `governance_url` |
| `config.json` | Snapshot of `inference_config` at time of champion promotion |
| `prompts/` | One file per prompt version, content-addressed filename |
| `source_bindings.json` | Declarative input resolution declarations |
| `write_targets.json` | Declarative output write declarations |
| `tool_authorizations.json` | Authorised tools and their configurations |
| `metadata.json` | `materiality_tier`, `application`, `channel`, `promoted_by`, `promoted_at` |

**Integrity check protocol:**

Before every run, the container:
1. Reads `manifest.json`
2. Computes SHA-256 of every other file in the bundle
3. Compares computed hashes against manifest entries
4. On any mismatch: aborts the run, publishes `INTEGRITY_VIOLATION` event to NATS, writes an error row to `execution_run_error` — before touching any data

**On-demand pull:** If no artifact is deployed, the container pulls the current champion bundle from MinIO using `registry_ref.json` as the address. This is the shared-infrastructure path for applications without a dedicated container.

**Deployment topologies:**

- **Owned container** (high-materiality): Dedicated `verity-runtime` Deployment for one application, with its own resource quotas, HPA rules, and network policies. Configured with `VERITY_WORKER_APPLICATION=<app_name>`.
- **Shared container** (low-materiality): Default `verity-runtime` fleet. Claims runs for any application. Configured with `VERITY_WORKER_APPLICATION=*`.

---

### 3.3 NATS JetStream as the event and dispatch layer

NATS JetStream replaces the Postgres polling loop for run dispatch and provides the event streaming infrastructure for real-time execution visibility.

**Why NATS is required (not optional) once Postgres HA is in place:**

Postgres `LISTEN/NOTIFY` does not replicate across Postgres nodes. Once Postgres HA is in place (primary + replicas), cross-node fan-out requires a dedicated broker. SSE handlers on any `verity-governance` replica must receive events published by a worker on any `verity-runtime` replica. NATS provides this; Postgres LISTEN/NOTIFY does not.

**Broker comparison:**

| Option | Verdict | Reason |
|---|---|---|
| Postgres LISTEN/NOTIFY | Single-node only | Breaks when SSE handlers connect to replicas |
| Redis Pub/Sub | No durability | Missed events are gone; requires Redis Streams for durability |
| Redis Streams | Viable alternative | Choose if Redis is already in the stack; same outcome, one fewer new service |
| **NATS JetStream** | **Selected** | 20MB binary, 3-replica HA, durable consumer groups, sub-ms dispatch, runs identically on laptop and K8s |
| Kafka / Redpanda | Overkill | 10× ops weight; warranted only when downstream consumers need Kafka-wire compatibility |
| AWS SQS + SNS | Cloud-only | Zero ops burden but vendor lock-in; choose if deploying exclusively to AWS |

**NATS subject design:**

| Subject | Purpose |
|---|---|
| `verity.runs.pending` | New run submitted; per-cluster **coordinators** subscribe via durable consumer group |
| `verity.cluster.{id}.commands` | Hub → coordinator control commands (patch, deploy_package, drain, …) |
| `verity.events.{run_id}` | Per-run execution events (turn, tool calls, completion) |
| `verity.decisions.stream` | Terminal decision records; consumed by decision log writer and analytics projector |
| `verity.worker.heartbeat.{worker_id}` | Per-container 30s liveness signal |
| `verity.integrity.violations` | Artifact integrity check failures |

**Transactional outbox pattern:**

The governance API never publishes directly to NATS. On run submission:
1. Single Postgres transaction inserts `execution_run` AND `harness_dispatch` (`queued`) AND `run_dispatch_outbox` (`pending`)
2. `verity-relay` service reads unpublished outbox rows (`SKIP LOCKED`), publishes to NATS, marks `published_to_cluster_at`
3. `verity-dispatch-sweep` CronJob (every 60s) catches messages published but not claimed within 5 minutes and re-publishes
4. The target cluster's elected **coordinator** subscribes and **claims via the Harness Gateway API** — the atomic `SKIP LOCKED` claim runs **hub-side** inside the gateway ([[0003-harness-governance-api]]: the spoke holds no DB credential), which marks `harness_dispatch` claimed/assigned. NATS redelivery and the dispatch-sweep are the two independent at-least-once layers.
5. The coordinator (the cluster's sole hub uplink) dispatches the claimed run to a worker over cluster-local NATS; workers never call the hub or the database directly.

> **Runtime architecture:** the per-cluster coordinator, the heartbeat-lease election, the operator/coordinator split, island-mode resilience, and the API-only claim are fixed in [[0010-harness-runtime-federated-coordinator]]. `core.harness_dispatch` is the mutable operational dispatch state; `core.execution_run_status` is its append-only audit (written in the same transaction).

**Feature flag:** `VERITY_DISPATCH_MODE=nats|postgres` — `postgres` poll loop kept as instant fallback.

---

### 3.4 Event streaming and real-time execution visibility

`ExecutionEvent` is wired to a transport from day one in v2. Not deferred.

**Event flow:**

```
Container executes run
  → publishes ExecutionEvent to NATS: verity.events.{run_id}
  → also inserts into runtime_event table (durable replay)

verity-governance SSE endpoint: GET /api/v1/runs/{run_id}/events
  → subscribes to NATS subject
  → streams events to connected client as text/event-stream
  → closes when terminal event (completed | errored) arrives

Multiple governance replicas can all serve SSE for the same run.
NATS fan-out handles it. No coordination needed.
```

**Execution event kinds:**

```
turn_started | tool_called | tool_returned | claude_responded | decision_logged | completed | errored
```

**Application status options:**

1. **Streaming (preferred):** `GET /api/v1/runs/{run_id}/events` — live events as they happen
2. **Polling (fallback):** `GET /api/v1/runs/{run_id}` — reads `execution_run_current` view; returns `current_status`, `duration_ms`, `error_code`
3. **Post-completion:** `GET /api/v1/decisions/{decision_log_id}` — full audit record

> **The analytics store is never in the status path.** It is a write-optimised reporting sink. Applications check NATS (via SSE) or `execution_run_current` — not the analytics store.

---

### 3.5 Postgres high availability from day one

A single-instance Postgres is not acceptable for a system holding the canonical governance metamodel and immutable decision log.

**Requirements:**

- Primary + at least one read replica, automatic failover
- PITR with minimum 7-day retention for the governance database
- Separate Postgres clusters for governance (`postgres-governance`) and vault (`postgres-vault`)
- Governance API writes → primary; read-heavy UI queries → read replica
- CloudNativePG is the reference implementation for self-hosted K8s
- RDS Multi-AZ or AlloyDB are acceptable managed alternatives

---

### 3.6 View on Verity — run detail and decision log UI

The Verity governance UI gains a first-class run detail view.

**Data sources for the run detail page:**

| Source | When | What it provides |
|---|---|---|
| `execution_run_current` view | Always | `current_status`, `submitted_at`, `first_started_at`, `current_worker_id`, `duration_ms` |
| SSE stream (`verity.events.{run_id}`) | While in-flight | Live `turn_started`, `tool_called`, `tool_returned` events |
| `agent_decision_log` | After completion | `input_json`, `output_json`, `tool_calls_made`, `source_resolutions`, `target_writes`, `inference_config_snapshot`, `message_history` |
| `model_invocation_log` + `v_model_invocation_cost` | After completion | Token counts, per-turn detail, cost breakdown |

**Page logic:**

```
Load execution_run_current → render status tile

if current_status not terminal:
  subscribe to SSE stream → render events as they arrive

when completed event arrives (or already terminal):
  load agent_decision_log by decision_log_id
  render full input/output, tool calls, source/target audit, cost
```

---

### 3.7 Packages as deployment targets; lifecycle-gated environments

Tasks and agents are promoted into **packages** (`.vtx`/`.vax`) that are the unit of
deployment. A package's **lifecycle state gates which environment it may run in and in
what mode**: `staging` → non-prod (live); `shadow` → prod read-only; `challenger` → prod
read-only or A/B; `champion` → any environment (live); `deprecated` → any environment
(locked; audit/replay only, cleanup allowed). "Read-only" means the harness executes and
logs decisions but its **Target Bindings are suppressed** — no business side effects.

Each package declares its **compatible harness image(s) by immutable digest**, tracked on
the registry; the governance deploy path **refuses incompatible package×image
combinations**, and an old package can be replayed on its original image on an ephemeral
cluster for reproducible audit. **All deployment is mediated by the governance control
plane** (the deploy-plane analog of [[0003-harness-governance-api]]) with a deployment
inventory of what runs where; out-of-band deploys are disallowed. See
[[0006-packages-and-governed-deployment]].

### 3.8 Decision-log scale and customer-portable analytics

Decision and model-invocation logs are **append-only**, ingested via the API's
async/batched path so many applications write concurrently. Analytics is a separate,
latency-tolerant read tier (reports run as **jobs**), persisted in an **open columnar
format (Iceberg/Parquet on object storage)** for cost-efficiency and scale, with a
documented **export seam so customers can port their reporting data into their own data
warehouse**. The pipeline shape — canonical append-only log → columnar projection →
portable export — is committed; the query engine is an open decision. See
[[0007-decision-log-scale-and-portable-analytics]] (extends [[0004-storage-architecture]]).

### 3.9 Compliance model: regulatory → canonical → controls & evidence

v2 replaces v1's `canonical requirement → Verity feature` mapping with a **three-axis,
two-bridge** model ([[0008-compliance-control-evidence-model]]). **Regulatory frameworks
and their citable provisions** (left) map many-to-many — by **minimum tier** — to a
**stable center axis of canonical requirements**; canonical requirements are grouped into
**governance domains** and decomposed into cumulative **tier ladders**; each requirement
binds, per tier and per lifecycle phase, to **controls** (type, phase, enforcement action)
and **evidence specifications** (right). New regulations insert by mapping provisions onto
existing canonical requirements without restructuring the center, and without duplicating
obligations.

Controls enforce at **four lifecycle phases**, each landing on existing v2 machinery:
**design-time** (intake/compose), **deploy-time** (the governed-deployment gate,
[[0006-packages-and-governed-deployment]]), **static/model controls** (the champion
package at rest), and **execution controls** (the runtime harness). Controls block
non-compliant activity at the point of occurrence; evidence is an append-only audit fact;
every **exception** is a first-class audit record (waived tier, affected requirement,
named approver, compensating controls, expiry). From **intake** onward the platform
resolves the applicable canonical requirements and drives the required controls/evidence
through the asset's lifecycle, and **maturity is scored per governance domain** (normalized
across variable tier ladders). The canonical vocabulary is largely carried over from the
data-governance platform; the model *around* it is the change. Governance is
**continuous**, not periodic.

---

## 4. Spec-Driven Development Methodology

Verity v2 is built 100% specification-first. This is a binding methodological commitment, not a preference.

### Specification hierarchy

1. **Architecture Decision Records (ADRs)** — one per significant design decision. Written before any implementation begins. Documents context, decision, consequences, alternatives considered. Cannot be overridden by implementation without a superseding ADR.

2. **Component specifications** — one per service or major subsystem. Defines API contract (OpenAPI 3.1), data model changes, event contracts (NATS subject and payload schemas), acceptance criteria, non-functional requirements.

3. **Feature specifications** — one per user-facing capability. Defines user story, functional requirements, API surface, database changes, test scenarios (happy path + failure modes).

4. **Implementation** — written to satisfy the spec. If implementation diverges, the spec is updated first via a documented amendment.

5. **Acceptance tests** — written from the spec's acceptance criteria before implementation begins. A feature is not done until its acceptance tests pass.

### Gates (enforced, not advisory)

- ADR written and reviewed before any architectural decision is implemented
- Component spec covers API contract, data model, event contracts, and acceptance criteria before implementation starts
- Acceptance tests written (even as stubs) before implementation starts
- No code merged without a traceable link to a spec item
- No spec item implemented before the spec is reviewed

### Repository structure

```
verity-v2/
├── specs/
│   ├── adrs/                    # Architecture Decision Records
│   ├── components/              # Per-service component specifications
│   ├── features/                # Per-feature functional specifications
│   ├── schemas/                 # OpenAPI 3.1 specs, NATS payload schemas
│   ├── contracts/               # Inter-service contracts
│   └── schema/
│       └── verity_schema.sql    # Canonical DB spec (carried from v1)
├── tests/
│   └── acceptance/              # Acceptance tests written from spec criteria
├── services/
│   ├── verity-governance/
│   ├── verity-runtime/
│   ├── verity-vault/
│   └── verity-relay/
├── k8s/
│   └── charts/
│       └── verity/              # Helm chart
└── docs/
    └── legacy-reference/        # v1 docs preserved as reference
```

---

## 5. Scalability Gap Analysis

Current v1 status per layer, and what v2 addresses:

| Layer | v1 status | v2 approach |
|---|---|---|
| `verity-api` replicas | ✅ Already stateless | HPA + load balancer, no code change needed |
| Worker replicas | ✅ SKIP LOCKED correct | HPA on NATS queue depth |
| Run dispatch | ⚠️ Postgres poll loop (~10 worker limit) | NATS outbox pattern |
| Event streaming | ❌ Unwired | NATS subjects + SSE bridge, day one |
| Postgres reads | ✅ Append-only, fast views | Read replica for UI queries |
| Postgres HA | ❌ Single instance | CloudNativePG HA, day one |
| Execution artifact | ❌ Does not exist | `.vtx`/`.vax` with integrity check, day one |
| Authentication | ❌ None | API keys + sessions, day one |
| Observability | ❌ Logs only | Prometheus + OTEL + Grafana, day one |

---

## 6. Implementation Roadmap

> **Amended 2026-05-30 (product-owner directive).** The roadmap is **feature-driven and
> vertical-slice-first**, so each phase is a meaningful demonstration that enables careful
> feature and architecture refinement (Constitution Principle VI). **Infrastructure is not
> a standalone phase** — K8s/Helm, HA Postgres, NATS, object store, and the image registry
> are enabling work **pulled into the phase that first requires them** (called out per
> phase). The hardened schema ([[0005-schema-hardening]]) is the **foundation** every phase
> extends, not a one-time step. The previous infra-first roadmap is superseded.

Each phase delivers a demonstrable, deployable increment. No phase depends on a later phase to function.

### Phase 0 — Foundation: hardened schema + ADRs
**Deliverable:** ADRs accepted; the hardened schema's foundational slices (Constitution Principle II); spec/test discipline scaffolded; OpenAPI 3.1 skeleton.  
**Gate:** ADRs + schema foundation reviewed; spec-first gates active. *Enabling infra:* local K8s (Docker Desktop) as a local-dev convenience only.

### Phase 1 — Intake
**Deliverable:** The human governance entry point — onboard an application/use-case, AI-risk classification, the intake workflow and its approval primitives.  
**Gate:** A reviewer completes an intake end-to-end in the UI; risk tier assigned; intake recorded in the governance metamodel. Demo-ready.

### Phase 2 — Registry & Compose
**Deliverable:** Entity model (agents, tasks, prompts, tools, inference configs, connectors, MCP); Source/Target Binding composition ([[binding-grammar]]); SCD-2 versioning; champion-resolution scaffolding.  
**Gate:** Author and compose an agent/task from registered parts; versions tracked; bindings declared. Demo-ready.

### Phase 3 — Harness, Packaging & Deployment
**Deliverable:** Harness image; `.vtx`/`.vax` packaging at promotion with SHA-256 integrity; **image-digest compatibility** and **governed deployment** with the lifecycle→environment matrix and deployment inventory ([[0006-packages-and-governed-deployment]]); a decision-logging **stub**.  
**Gate:** A package deploys through governance to a non-prod cluster on a compatible image; an incompatible deploy is refused; the inventory reflects what runs where. *Enabling infra:* object store + image registry pulled in here. Demo-ready.

### Phase 4 — Decision Logging
**Deliverable:** Canonical append-only decision + model-invocation logs via async/batched API ingest ([[0003-harness-governance-api]], [[0004-storage-architecture]]); Tier-1/Tier-2 seam (Postgres-only to start).  
**Gate:** A run writes a complete decision log; the UI renders it (latency-tolerant). Demo-ready.

### Phase 5 — Testing
**Deliverable:** Validation runs, ground-truth datasets, an acceptance harness that executes packages and compares against expected outputs.  
**Gate:** A package runs against a ground-truth set; pass/fail and metrics are recorded. Demo-ready.

### Phase 6 — Lifecycle / Promotion
**Deliverable:** Full 6-state lifecycle (`draft → … → champion → deprecated`; `shadow`/`ab` are challenger run-modes; rollback restores deprecated); approval records; promotion gates; state-transition-driven deployment placement (ADR-0006 matrix).  
**Gate:** An entity is promoted through the lifecycle with documented approvals; each transition drives the correct environment placement/mode. Demo-ready.

### Phase 7 — Production-like Run
**Deliverable:** The infrastructure a real prod run requires, pulled in here — HA Postgres (CloudNativePG), NATS JetStream dispatch (transactional outbox via `verity-relay`), event streaming + SSE, owned vs shared containers, HPA.  
**Gate:** Submit a run → dispatched via NATS → executed on an owned/shared container → live events stream to the UI → decision logged → visible in `execution_run_current`. Demo-ready.

### Phase 8 — Compliance Framework
**Deliverable:** The three-axis compliance metamodel ([[0008-compliance-control-evidence-model]]) — regulatory frameworks/provisions, canonical requirements + governance domains + tier ladders, controls (per phase) and evidence specifications, with the regulatory mappings (SR 11-7, NAIC, CO SB21-169, NIST RMF, ISO 42001); design/deploy/static/execution control enforcement wired to the phases built in earlier phases; append-only evidence + first-class exceptions; per-domain maturity scoring.  
**Gate:** A champion's compliance dossier assembles from controls + captured evidence (not features): every applicable canonical requirement shows its tier, the enforcing controls per phase, the evidence on record, and any registered exceptions; per-domain maturity is scored and exportable. Demo-ready.

### Phase 9 — Reporting / Analytics
**Deliverable:** Tier-2 columnar analytics (open Iceberg/Parquet substrate), reporting jobs, and **customer-portable warehouse export** ([[0007-decision-log-scale-and-portable-analytics]]).  
**Gate:** Reports run as jobs at multi-application volume; a customer can port their reporting data into their own warehouse. *Enabling infra:* object-store analytics tier + query engine pulled in here. Demo-ready.

---

## 7. Open Decisions

The following must be resolved before Phase 0 specification work can be finalised.

| # | Decision | Options | Impact if deferred |
|---|---|---|---|
| 1 | Message broker | NATS JetStream (recommended) · Redis Streams (if Redis already present) · AWS SQS+SNS (if cloud-only) | Phase 3 and Phase 4 cannot be specced |
| 2 | Postgres HA provider | CloudNativePG · AWS RDS Multi-AZ · GCP AlloyDB · Azure Database for PostgreSQL | Phase 1 infra spec cannot be finalised |
| 3 | Artifact object store | MinIO (self-hosted) · AWS S3 · GCS · Azure Blob | Phase 3 artifact packaging cannot be specced |
| 4 | Target K8s environment | Docker Desktop K8s · EKS · GKE · AKS · on-prem | Helm chart defaults and NetworkPolicy design depend on target |
| 5 | Authentication provider | **RESOLVED (2026-05-30)** — Microsoft Entra ID (OIDC, Authorization Code + PKCE) for human users + app-scoped API keys for the harness; plus an env-var-gated local **mock-auth** mode for dev/test. DB-managed roles, decoupled from the IdP. See [[user-authentication]] (FR-030 covers mock auth). | — |
| 6 | Owned container provisioning | Auto at champion promotion · Manual by ops · Self-service via governance API | Phase 3 deployment model depends on this |

---

## 8. What This Document Is For Claude Code

When used as a Claude Code project document, this PCR serves as:

- **The authoritative intent document** for all v2 implementation work. Any ambiguity in a spec or implementation question should be resolved by reference to this document first.
- **The "carry forward" list** for Phase 0 spec work. The schema in `specs/schema/verity_schema.sql` is the source of truth for all data model decisions.
- **The "do not copy" boundary.** No Python source from v1 is copied into v2. Implementation is written against specs, with v1 as reference only.
- **The gate document.** Phase 0 is complete when all open decisions in Section 7 are resolved and all component specs are drafted. No implementation (Phase 1+) begins before Phase 0 is closed.

---

## 9. Approval

This PCR requires sign-off before Phase 0 (specification work) begins. Approval constitutes agreement that:

- [ ] Verity v2 is a new repository, built from an empty state against this PCR and subsequent specs
- [ ] Verity v1 is retained as the legacy reference implementation and is not deleted or modified
- [ ] Open decisions in Section 7 are resolved before Phase 0 specification work begins
- [ ] No implementation code is written until the relevant component spec is reviewed and accepted
- [ ] The schema from v1 (`schema.sql`) is the canonical database specification for v2

| Role | Name | Date |
|---|---|---|
| Product Owner | | |
| Architecture Lead | | |
| Engineering Lead | | |
| Compliance Owner | | |

---

*Verity v2.0 Product Change Request v0.2 — May 2026 — CONFIDENTIAL*
