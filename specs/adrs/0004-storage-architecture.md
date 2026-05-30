# ADR-0004 — Storage architecture: thin Postgres + bulk log store, insert-only

- **Status:** Accepted
- **Date:** 2026-05-29
- **Deciders:** Product Owner (Anil)
- **Related:** [[0003-harness-governance-api]], [[0005-schema-hardening]]

---

## Context

The governance metamodel (entities, versions, lifecycle, configs) is **low-volume,
relational, and read-often** — Postgres is the right home. But the audit data —
`agent_decision_log`, `model_invocation_log`, runtime events — is **high-volume,
append-heavy, and queried analytically** (reporting, the UI's run views). Keeping bulk
logs in the same Postgres instance couples a fast-growing, write-heavy workload to the
system of record and does not scale.

Separately, for scalability the transactional model should avoid in-place mutation:
update/delete churn creates contention, bloat, and a weaker audit story.

## Decision

Adopt a **tiered storage architecture** with an **insert-only transactional model**.

**Tier 1 — thin Postgres (system of record).** Holds the governance metamodel and
transactional run *state*: registry, versions, lifecycle, configs, the run state
machine, and the override records. This stays small and relational.

**Tier 2 — bulk log store (analytics + audit at volume).** High-volume logs —
decision logs, model-invocation logs, runtime events — are written to a
**storage-efficient columnar store** (Apache Iceberg tables on object storage) with a
**query engine on top** (DuckDB, or equivalent) for the UI and reporting. Both the
admin UI and reporting read from this tier; it is never in the live invocation path.

**Insert-only / append-only transactions.** Transactional operations are modeled as
**appends, not updates**. State changes are new rows (the run state machine is already
event-sourced this way in v1 via `execution_run_status`); current state is a view over
the latest event. No destructive in-place mutation of transactional records.

All of this sits **behind the governance API** ([[0003-harness-governance-api]]): the
harness and applications write through API ingest endpoints and never see which tier a
write lands in. High-volume writes use **batched / async ingest** so the HTTP hop does
not bottleneck execution.

> Iceberg + DuckDB are the **reference choice**, not a hard commitment. The binding
> decision is the *two-tier shape* and *insert-only model*; the specific engine is
> confirmed during the storage component spec. (PCR §7 open decisions on broker/HA are
> separate and remain deferred — local Docker first.)

## Consequences

**Positive**
- The system of record stays small, fast, and easy to back up / replicate.
- Bulk audit data grows on cheap object storage with columnar compression; analytical
  queries hit a purpose-built engine.
- Insert-only gives a naturally complete audit trail and removes update contention — a
  direct scalability win.
- The storage topology can evolve behind the API without touching harness or apps.

**Negative / costs**
- Two stores to operate and keep consistent; "current state" is a projection/view, not
  a single mutable row (a deliberate trade).
- Reporting/UI queries must target the right tier; the query-engine layer is new
  infrastructure to stand up (deferred past the first slice — start with Postgres-only
  and introduce Tier 2 before logs grow).
- Async/batched ingest adds delivery-semantics complexity on the write path.

## Alternatives considered

**Single Postgres for everything (v1 model).** *Rejected* for scale — bulk logs starve
the system of record and balloon the database.

**Update-in-place transactional tables.** *Rejected* — contention, bloat, and a weaker
audit story; insert-only is both more scalable and more auditable.

## Phasing note

The equity-research slice runs **Postgres-only** to stay simple. The insert-only model
is adopted from day one (it is a schema-design rule, see [[0005-schema-hardening]]); the
Tier-2 bulk store is introduced as a dedicated phase before log volume warrants it, not
in the first slice.
