# ADR-0003 — Harness ↔ governance communication is API-only

- **Status:** Accepted
- **Date:** 2026-05-29
- **Deciders:** Product Owner (Anil)
- **Related:** [[0002-execution-model]], [[0004-storage-architecture]]

---

## Context

[[0002-execution-model]] places the harness *inside the business application*. That
raises a concrete question: how does a distributed harness read what it needs (champion
artifact, registry metadata) and write what it produces (run state, decision log, HITL
overrides) back to centralized governance?

Two options:
- **Direct database access** — the harness holds governance DB credentials and
  reads/writes Postgres directly (this is effectively how v1's in-process worker
  behaves, sharing the pool).
- **API only** — the harness talks exclusively to the governance API over HTTP; it
  never holds DB credentials.

## Decision

**The harness communicates with governance exclusively through the governance API.**
It never connects to the governance database directly.

- **Reads** (registry lookup, champion artifact metadata) go through API endpoints.
- **Writes** — run lifecycle transitions, the decision log, model-invocation logs, and
  HITL overrides — go through API endpoints (e.g. the existing
  `POST /api/v1/runs/{decision_log_id}/overrides` shape, confirmed in v1).
- The harness carries an **API credential**, scoped to its application; it carries no
  database credential.
- The governance API owns all writes to the storage layer, including routing
  high-volume logs to the bulk store per [[0004-storage-architecture]]. The harness is
  unaware of the storage topology behind the API.

## Consequences

**Positive**
- Applications never hold central DB credentials — a hard security and blast-radius
  boundary, which is the point of the distributed model.
- The storage topology (thin Postgres + bulk log store) can change behind the API
  without touching any harness.
- One enforcement point for validation, auth, quotas, and audit on every write.
- The API contract becomes the single, testable seam between execution and governance.

**Negative / costs**
- An HTTP hop on the write path; high-volume decision/invocation logging must be
  designed for it (batching / async ingest endpoints), which ties directly to
  [[0004-storage-architecture]].
- The governance API must expose ingest endpoints for everything the harness writes —
  part of the full API surface ([[0001-rebuild-vs-refactor]]).

## Alternatives considered

**Direct DB access from the harness.** *Rejected.* It re-couples execution to the
governance database, spreads DB credentials to every application, and locks the storage
topology in place. The only upside (lower write latency) is better solved with
batched/async ingest endpoints.

## Notes

The in-process SDK path remains valid for *co-located* callers as a convenience
(skip the HTTP hop), exactly as v1 documents on the override endpoint. The
**distributed harness**, however, is API-only — the SDK shortcut is not available to it
because it does not share a process with governance.

---

## Amendment — 2026-06-09 (ADR-0015)

**Pre-signed URL upload pattern added.** For large artifact uploads (per-run decision
logs, execution event files, error records), proxying bytes through the hub is wasteful
and unnecessary. The API-only boundary is satisfied by negotiation, not by data transfer:

The harness requests a **pre-signed PUT URL** from the Harness Gateway API at run start.
The hub generates the URL scoped to `{tenant_id}/runs/{yyyy}/{mm}/{dd}/{run_id}/` using
its own object store credential (never shared with the harness) and returns it. The
harness uploads files **directly to object storage** using the short-lived URL. Bytes do
not proxy through the hub.

The harness includes `log_path` and `decision_log_id` in the `release` call to the
Harness Gateway. The hub stores the path in `execution_run` and generates pre-signed
**download** URLs on demand when `GET /runs/{run_id}` is called.

The harness holds no long-lived object store credential — only the short-lived
per-run pre-signed URL minted by the gateway. This satisfies the API-only boundary: every
storage interaction is negotiated through the gateway; the harness never holds the
credential that authorises the storage account.
