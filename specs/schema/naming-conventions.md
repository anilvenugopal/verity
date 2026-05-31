# Schema — Naming & structure conventions (v2 hardened)

- **Status:** Draft
- **Date:** 2026-05-31
- **Related:** [[0005-schema-hardening]], [[0004-storage-architecture]], [[binding-grammar]]

---

## Purpose

This is the single canonical naming and structure standard for the v2 hardened schema.
It operationalizes [[0005-schema-hardening]] rules 1–4: one convention applied
uniformly across tables, columns, enums, indexes, foreign keys, and views; proper
structure with explicit keys, types, and real constraints; insert-only transactions
with current state as a view; and explicit Tier-1 vs Tier-2 tagging. Every rule here is
mandatory for schema artifacts under `specs/schema/` and for the generated DDL. v1 is a
behavioral reference only — none of its naming inconsistencies carry forward.

---

## 1. Casing

- All identifiers are `snake_case`: tables, columns, constraints, indexes, enum types,
  enum members, views, schemas. No camelCase, no PascalCase, no quoted mixed-case
  identifiers anywhere.
- Lowercase only. Words separated by single underscores. No abbreviations unless they
  are domain-standard (`pdf`, `mcp`, `llm`, `id`, `url`).
- Reserved words are never used as identifiers (e.g. no column named `order`, `user`,
  `type` — use `entity_type`, `account_user`, etc.).

## 2. Tables

- **Singular** table names: `agent`, `task`, `agent_version`, `execution_run`,
  `source_binding`, `target_binding`. Not `agents`, not `tasks`.
- A table name is the singular noun for one row of that thing. Join/junction tables are
  named for the relationship: `<a>_<b>` (e.g. `agent_version_tool`), singular on both
  sides.
- Tables live in a named schema (`governance.<table>`), never the bare `public` schema.
- Event tables (append-only) are named `<entity>_event` or with a domain-event noun
  (`execution_run_status`); the matching current-state view is `<entity>_current`
  (§7).

## 3. Primary keys (surrogate)

- Every table has a single surrogate primary key. No natural or composite PKs as the
  row identity.
- Column name is `<table>_id` (the table's own name + `_id`), **not** a bare `id`. This
  makes the column self-describing in joins and removes the v1 ambiguity of every table
  having `id`.
- Type and default are fixed:

  ```sql
  agent_id  uuid  PRIMARY KEY  DEFAULT uuidv7()
  ```

- `uuidv7()` (time-ordered UUIDv7) is the mandated generator — its monotonic prefix
  gives index locality and naturally orders inserts, which matters for the append-only
  event tables and for Tier-2 BRIN locality (§8). Do not use `uuid_generate_v4()` /
  `gen_random_uuid()` (v1 used v4; v2 replaces it).
- Constraint name for the PK is `pk_<table>`.

## 4. Foreign keys

- FK columns are named `<ref_table>_id`, matching the referenced surrogate PK
  (`agent_id`, `inference_config_id`). When a table has two FKs to the same target, the
  column carries a role prefix: `cloned_from_version_id`, `current_champion_version_id`.
- The FK **constraint** is named `fk_<table>_<ref>` where `<table>` is the child and
  `<ref>` is the referenced table (or the role, when disambiguating):

  ```sql
  CONSTRAINT fk_agent_version_agent
      FOREIGN KEY (agent_id) REFERENCES governance.agent (agent_id),
  CONSTRAINT fk_agent_version_cloned_from
      FOREIGN KEY (cloned_from_version_id) REFERENCES governance.agent_version (agent_id)
  ```

- **ON DELETE guidance:**
  - Default to `ON DELETE RESTRICT` for all Tier-1 system-of-record references — the
    governance metamodel must never lose a row by cascade.
  - `ON DELETE CASCADE` only for owned child rows whose existence is meaningless
    without the parent **and** which are not themselves audit records (e.g. a binding
    row owned by the version that declares it). Document each cascade in the table spec.
  - `ON DELETE SET NULL` only for genuinely optional/nullable references (e.g.
    `cloned_from_version_id` when the ancestor is purged).
  - Append-only event tables are **never** the target of a cascade and never define
    cascading deletes outward — audit rows are immutable (§7).
- Every FK column is indexed (§6) unless it is also the leading column of an existing
  index.

## 5. UNIQUE & CHECK constraints

- **UNIQUE** constraint name: `uq_<table>_<col>[_<col>...]`:

  ```sql
  CONSTRAINT uq_agent_version_agent_id_semver UNIQUE (agent_id, semver)
  ```

- **CHECK** constraint name: `ck_<table>_<rule>`, where `<rule>` describes the invariant
  in words, not the columns:

  ```sql
  CONSTRAINT ck_execution_run_ended_after_started CHECK (ended_at >= started_at),
  CONSTRAINT ck_target_binding_target_kind_known   CHECK (target_kind IN ('vault','task_output','structured'))
  ```

- CHECK constraints must encode **real domain invariants** (ADR-0005 rule 2), not
  restate types. Prefer an `enum` type (§9) over a CHECK-on-text for closed value sets.
- NOT NULL is applied wherever a value is always required; nullability is a deliberate,
  documented choice, not a default.

## 6. Indexes

- Index name: `ix_<table>_<col>[_<col>...]`. Partial indexes append a `_<predicate>`
  qualifier: `ix_execution_run_status_active_only`.
- Every FK column has a btree index `ix_<table>_<fk_col>` (covers join + cascade
  performance) unless redundant with a composite index that leads on it.
- Unique indexes backing a constraint are expressed as the UNIQUE constraint (§5), not a
  separate `CREATE UNIQUE INDEX`, so the name is `uq_*`.
- Tier-2 tables use **BRIN** indexes on `created_at` rather than btree (§8); BRIN index
  name: `brin_<table>_created_at`.

## 7. Append-only event tables + current-state views

ADR-0004 and ADR-0005 rule 3: transactional records are **appended, never mutated in
place**; "current state" is a **view** over the latest event. This generalizes v1's
event-sourced run model (`execution_run_status`).

Rules:

- An event table holds one immutable row per state transition. It has its own
  `<table>_id` surrogate PK (UUIDv7, time-ordered), the owning entity FK, a
  `created_at timestamptz`, and the event payload. No `updated_at`, no in-place
  UPDATE/DELETE — events are facts.
- The current-state projection is a VIEW named `<entity>_current` that selects the
  latest event per entity (typically `DISTINCT ON (<entity>_id) ... ORDER BY
  <entity>_id, created_at DESC`, or a window function).
- Consumers read the view for "what is the state now"; writers only INSERT into the
  event table. The view is never materialized in Tier-1 (it stays a live projection);
  if performance warrants, materialization is a Tier-2 concern.

### Worked example — execution run state machine
