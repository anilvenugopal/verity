# ADR-0012 — Data access (raw SQL via aiosql + thin repo) and migrations

- **Status:** Accepted
- **Date:** 2026-06-02
- **Deciders:** Product Owner (Anil)
- **Related:** [[0005-schema-hardening]], [[0011-repository-topology-and-harness-release-boundary]]

---

## Context

CLAUDE.md mandates **raw SQL, no ORM**. The schema is large (172 base tables), heavily
normalized, and leans on Postgres features an ORM handles poorly: RANGE partitioning, partial
unique indexes, `SKIP LOCKED` claims, `DISTINCT ON` current-state views, SCD-2 temporal joins
(point-in-time cost), pgvector, and CTEs. Verity is also a governance/audit product where the
**database is the system of record** and being able to review the exact SQL that touched data
is a compliance property, not a convenience.

"No ORM" still leaves a spectrum: naked SQL strings, raw SQL organized in files, a typed SQL
builder (SQLAlchemy Core, no ORM), or a full ORM. The full ORM fights the schema and hides the
SQL — rejected outright. The choice was between organized raw SQL and SQLAlchemy Core; the
trade is *control / DB-as-truth* vs *refactor-safety / generated SQL*.

## Decision

**Raw SQL lives in versioned `.sql` files, loaded as named functions via `aiosql`, behind a
thin repository layer; Pydantic v2 validates at the boundary; migrations are hand-written,
numbered SQL applied by a small runner.**

- **Queries** are `.sql` files (one per aggregate/table) with named, documented statements;
  `aiosql` exposes them as Python functions over psycopg v3. The SQL stays literal and
  reviewable — a DBA can read it, and it is what runs.
- **A thin repository layer** removes the repetitive 70%: helpers build INSERT column lists
  from Pydantic models and map rows back to them. No identity map, no lazy loading, no
  query generation.
- **Pydantic v2** models are the boundary types (request/response, row mapping); they are not
  persistence objects.
- **The PG18 testcontainer is the safety net.** Raw SQL loses compile-time column checks, so
  every query is covered by a test against a real Postgres 18 (the same image the schema load
  test uses). Column drift fails CI, not prod.
- **Migrations** are forward, numbered SQL files (`NNNN_*.sql`) tracked in a
  `schema_migrations` table, applied by a small in-house runner. The current canonical schema
  (`specs/schema/verity_schema.sql` + `seed/`) is the **baseline** (migration 0001). Sqitch is
  a clean later upgrade if deploy/verify/revert is wanted; we start dependency-light.

## Consequences

**Positive**
- The database/SQL stays authoritative — aligned with the audit/governance philosophy and
  [[0005-schema-hardening]].
- Full control over the advanced Postgres the schema depends on; no ORM impedance.
- Queries are centralized and reviewable (in `.sql` files), not smeared across Python.
- Boilerplate is bounded by the repo helpers; migrations are explicit and inspectable.

**Negative / costs**
- No compile-time column checking — mitigated by mandatory query tests against the PG18
  container (this is the load-bearing mitigation; let test coverage slip and refactors get
  risky).
- The in-house migration runner is ours to maintain (kept deliberately tiny; sqitch is the
  escape hatch).
- More query plumbing than an ORM for simple CRUD — accepted for the control it buys.

## Alternatives considered

- **SQLAlchemy Core + Alembic.** *Rejected (for now)* — refactor-safe and brings Alembic, but
  it *generates* SQL (a step from DB-as-truth), and you drop to raw SQL for the hard 30%
  anyway. Defensible; revisit if refactor-safety across the table count becomes the dominant
  pain.
- **Full ORM (SQLAlchemy ORM / SQLModel).** *Rejected* — hides SQL, invites N+1, fights
  partitioning/`SKIP LOCKED`/pgvector, makes Python classes the source of truth.
- **Naked psycopg strings.** *Rejected* — same control as aiosql but SQL smeared across Python
  and harder to audit/refactor.
- **Alembic with raw SQL only.** *Rejected* — Alembic's value is autogenerate from models;
  without them it is a heavier numbered-migration runner.

## Notes

This confirms (does not amend) the CLAUDE.md raw-SQL rule and fixes *how* raw SQL is organized
and how migrations work. The repository-helper API, the migration runner, and the `.sql` file
conventions are an implementation concern for the hub component scaffold.
