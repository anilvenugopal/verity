# ADR-0010 — Harness runtime: federated coordinator, enrollment, and resilience

- **Status:** Accepted
- **Date:** 2026-06-02
- **Deciders:** Product Owner (Anil)
- **Related:** [[0002-execution-model]], [[0003-harness-governance-api]],
  [[0006-packages-and-governed-deployment]], [[0004-storage-architecture]],
  [[0005-schema-hardening]], [[0007-decision-log-scale-and-portable-analytics]]

---

## Context

[[0002-execution-model]] adopted the **application-hosted harness** (a business app pulls
a Verity harness image + champion `.vax`/`.vtx` packages and executes locally);
[[0003-harness-governance-api]] fixed the **API-only boundary** (the harness never holds a
governance DB credential); [[0006-packages-and-governed-deployment]] made deployment a
governed control plane and explicitly **deferred "cluster orchestration mechanics … to the
runtime/deployment component spec."** This ADR closes that thread.

The open questions are operational, and they only get harder at the target scale of
**hundreds of clusters in production**:

1. How is the harness actually structured inside a customer cluster — one process, or a
   topology? Who leads when a cluster has many nodes?
2. How does work get queued and processed without the spoke ever touching the hub
   database (the [[0003-harness-governance-api]] invariant)?
3. How does the system stay correct when the hub, the network, or a node fails?
4. How does an app team go from "I have podman/k8s" to "connected and deploying from the
   portal," securely, with credentials they never hand to Verity?

The detailed design (timings, failure-scenario walk-through, volume math, full DDL) lives
in `specs/schema/HARNESS-ARCHITECTURE-PROPOSAL.md`. This ADR records the **decisions** and
why.

## Decision

**The harness is a federated hub-and-spoke runtime: a per-cluster elected coordinator
leads a pool of stateless workers, integrates with the hub exclusively through the Harness
Gateway API and NATS (never the database), and degrades to autonomous island mode when the
hub is unreachable.**

### 1. API-only is absolute — the spoke holds no DB credential

Every SQL statement that touches the governance database executes **hub-side**, inside a
**Harness Gateway API** handler. The coordinator and workers make **outbound HTTPS calls
only**; they never connect to Postgres. This re-affirms [[0003-harness-governance-api]] and
removes any ambiguity: the lease election, the dispatch claim, the run-state writes, and
the heartbeat upserts are all gateway endpoints, not spoke-side queries. Two named hub
processes sit behind this boundary: the **Harness Gateway API** (the spoke-facing REST
surface — register, claim, release, heartbeat, ack) and **verity-relay** (the background
publisher that drains the outboxes to NATS). They are distinct; "relay" never means a
spoke-side DB connection.

### 2. Operator and coordinator are split on k8s, merged on Linux

Two roles with different privilege and different cadence:

| | **Operator** (lifecycle control plane) | **Coordinator** (dispatch data plane) |
|---|---|---|
| Privilege | k8s API + RBAC (Deployments, image patch, HPA, ESO wiring) | none in k8s; hub API + app creds only |
| Touches customer data / model? | never | yes |
| HA | singleton (k8s-native `Lease`) | heartbeat-lease (works on bare Linux too) |
| Cadence | slow idempotent reconcile | fast leadership (~3-min failover) |

On **Kubernetes** these are separate Deployments: the operator is the *only* component with
cluster privileges and never touches customer data or the model; the coordinator/workers
never touch the k8s API. This is least-privilege — a compromised data-plane component
cannot rewrite the cluster. The app team's one-time `helm install` *is* the operator; it
then reconciles the coordinator/worker Deployments, image patches, and package config from
hub desired state, so they never run Helm again. On **bare Linux/podman** there is no RBAC
boundary to protect, so the operator's functions collapse into the coordinator's local
agent (driving `systemctl`/`podman`).

The split is reinforced by the two deployment command kinds (§5): `deploy_package` is a
coordinator action (no restart), `patch` is an operator action (Deployment roll).

### 3. Leadership is an elected coordinator via a heartbeat lease

A cluster elects **one coordinator** (master) among its `harness_node`s. Election is a
single **atomic** statement run hub-side on each coordinator heartbeat:

```
UPDATE core.harness_coordinator
   SET coordinator_node_id = $node, last_heartbeat_at = now(),
       lease_expires_at = now() + lease_duration
 WHERE deployment_cluster_id = $cluster
   AND (coordinator_node_id = $node OR lease_expires_at < now());
-- lease_held = (row_count > 0)
```

Row-level locking serialises competing claims, so **two standbys can never both win** — no
split-brain, **no advisory locks** (which would need a persistent spoke DB connection —
forbidden by §1 — and a hub watchdog for partitions), **no NATS JetStream KV** (an extra
dependency on every bare-Linux cluster). `lease_duration = 3 × heartbeat_interval` (6 min
default; tunable per cluster). Failover is ~3 min average; during it, **in-flight jobs keep
running** and only *new* dispatch pauses.

**Why a master at all** (vs. a stateless NATS consumer group): only a single per-cluster
leader can own island-mode state, global priority/concurrency/requeue decisions, and a
single health voice. These are core requirements, not nice-to-haves, so the coordinator is
necessary — not a heavier-than-needed choice.

### 4. The coordinator is the cluster's sole hub uplink

A cluster has **one hub identity** (its mTLS cert). **Workers reach the hub only through
the coordinator** (worker → cluster-local NATS → coordinator → Harness Gateway API). This
minimizes credential spread (workers hold no hub credential), gives a single auditable
egress point, and makes island-mode buffering fall out for free (it is just NATS not being
drained). The invariant that protects throughput: **in-flight execution never depends on
the coordinator** — a worker holds its claim, bundle, and credentials locally and finishes
the job even if the coordinator dies mid-flight; only *reporting* waits for the next
coordinator.

### 5. Dispatch path, and package-vs-image deployment

**Run dispatch (hub → cluster → worker):** governance writes `execution_run` +
`harness_dispatch` (`queued`) + `run_dispatch_outbox` (`pending`) in one transaction →
verity-relay publishes to NATS `verity.runs.pending` → the coordinator claims via the
gateway (`claimed`/`assigned`) → a worker executes (`executing`) → releases (`released`).
Four state surfaces, each with one job: `run_dispatch_outbox` = hub→NATS handoff;
`harness_dispatch` = mutable current claim/exec state the coordinator polls;
`execution_run_status` = append-only audit; `execution_run_current` = the live view.
**`harness_dispatch` and `execution_run_status` are written in one transaction** so they
cannot drift.

**Package deployment ≠ image deployment:**
- **`deploy_package`** (coordinator) swaps the `.vtx/.vax` bundle in the artifact cache and
  flips `deployment.deployment_status_code` (new `active`, old `superseded`). Bundles load
  **once at claim time**, so in-flight jobs finish on the bundle they started with; old and
  new bundles coexist in cache. **No drain.**
- **`patch`** (operator) replaces the harness **image** — a Deployment roll. Here the
  portal surfaces a **graceful vs. force** choice: graceful drains (stop accepting new
  dispatch, finish in-flight up to the timeout, then restart); force restarts immediately
  and in-flight jobs are requeued (`attempt_number+1`, new `write_idempotency_key`).

### 6. Resilience: island mode

A per-cluster **circuit breaker** on gateway calls (open after N=5 consecutive failures)
puts the coordinator into **island mode**: executing jobs continue (model API direct, local
artifact cache); events buffer in cluster-local NATS JetStream (bounded 10k/24h); new
dispatch pauses (the coordinator cannot claim without the hub); quota is enforced from a
**coordinator-local SQLite cache** (an operational cache only — the hub is always
authoritative; it holds the lease record, in-flight job copies, quota, and the artifact
manifest). On reconnect the coordinator replays the buffer, reconciles `harness_dispatch`,
refreshes quota, and resumes. There is **no Postgres inside the harness** — the durable
queue is central NATS, the system of record is the central Postgres behind the gateway, and
SQLite is a thin local cache.

### 7. Enrollment and credentials

**Connect:** the portal mints a one-time, short-lived enrollment token; the app team
installs the operator (k8s) or agent (Linux) with it; on first contact the spoke exchanges
the token for an **mTLS cert + app-scoped API key** (stored spoke-side; token consumed).
All traffic is **outbound-only TLS 1.3 on 443** — zero inbound ports. Certs auto-rotate on
a 7-day overlap window via a `patch_cert` command.

**App data-source credentials — Model B (metadata only):** the hub stores a credential's
**name, type, and verification result** and **nothing else** — no value, no vault ref. The
secret lives on the spoke (k8s Secret via External Secrets Operator from the customer's own
secrets manager; or an encrypted config file on Linux) and is read in-memory by the worker
at job time. The coordinator test-connects and reports
`credential_verification_status`. The hub knows a credential exists and whether it works,
**never what it is.**

### 8. Schema additions

All additions honor the three-schema rule ([[0005-schema-hardening]] D3 — `reference`,
`core`, `audit`); no new top-level schema. **All status fields are reference vocab tables**
— this ADR adopts that as universal and supersedes D1's native-enum hot-path exception
(the three former enums `outbox_status`, `run_status`, `run_completion_status` are now
`reference.*` tables).

New `core` tables: `harness_node`, `harness_coordinator`, `harness_dispatch`,
`harness_app_credential`, `harness_command_outbox`. New `reference` vocabs:
`run_dispatch_status`, `command_outbox_status`, `harness_node_status`,
`credential_verification_status` (+ the three converted). New columns:
`automation_actor.deployment_cluster_id` (soft ref — one automation actor per cluster, not
per instance, to avoid actor proliferation) and `execution_run_status.worker_node_id`
(soft ref to the executing host). New command kinds: `deploy_package`, `patch_cert`.
Directional clarity is baked in: every table in the chain opens its comment with a `LEG:`
line and transition columns name their actor (`published_to_cluster_at`,
`claimed_by_coordinator_at`, `assigned_to_instance_id`, `worker_started_at`, …).

## Consequences

**Positive**
- The [[0003-harness-governance-api]] boundary is airtight: no DB credential ever leaves
  the hub; the spoke is outbound-only.
- Scales to hundreds of clusters: central NATS fans out work, the gateway uses
  transaction-mode pooling, heartbeats are Tier-2 partitioned, and there is no per-cluster
  database to operate.
- Resilient by construction: split-brain is provably impossible; hub/network/node failures
  degrade to island mode without losing or double-running in-flight work.
- Least-privilege on k8s: only the operator holds cluster RBAC, and it never touches
  customer data or the model.
- Self-service onboarding: one operator install, then deploy from the portal forever;
  customers keep their own secrets.

**Negative / costs**
- More moving parts than a single poll loop: an operator, a coordinator with election, a
  gateway, a relay, SQLite, and a circuit breaker.
- New-dispatch latency during failover (≤6 min, ~3 min typical) — acceptable for a
  governance platform with 1–5s jobs, tunable via a shorter lease.
- The coordinator is load-bearing for dispatch and reporting (mitigated: execution is
  independent of it; failover is bounded).
- The Harness Gateway API must implement the atomic lease/claim correctly — the election's
  correctness lives there.

## Alternatives considered

- **Stateless NATS consumer group, no master.** *Rejected* — cannot own island-mode state,
  global priority/requeue, or a single health voice. (This supersedes the earlier
  no-master direction taken before island mode was a requirement.)
- **`pg_try_advisory_lock` for leadership.** *Rejected* — needs a persistent spoke→hub DB
  connection (violates §1), leaks the lock on a network partition (needs a hub watchdog),
  and forces session-mode pooling at scale.
- **NATS JetStream KV for leadership.** *Rejected* — an extra dependency on every cluster,
  including bare Linux, for something Postgres + a heartbeat already provides.
- **Per-instance automation actors / per-worker hub identities.** *Rejected* — actor and
  credential proliferation from pod churn; one actor and one mTLS identity per cluster
  instead, with node identity carried on the run-status event.
- **Hub-held / hub-proxied data credentials.** *Rejected* — makes Verity a custodian of
  customer secrets; Model B keeps values on the spoke.

## Notes

The detailed runtime design — lease timings, ten failure scenarios, heartbeat
specification, circuit-breaker backoff, and the complete DDL — is captured in
`specs/schema/HARNESS-ARCHITECTURE-PROPOSAL.md`. This ADR fixes the architecture; that
document and the 001 component spec carry the implementation detail.
