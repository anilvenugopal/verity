# Phase 1 — Data Model: Intake slice

This slice **adds no tables** — it uses existing canonical-schema entities (reviewed,
PG18-loaded). Field names below are the schema column names verbatim (naming gate). Full
column docs live in the catalog comments / `specs/schema/DATA-MODEL.md`.

## Entities used (Tier-1, `core`)

### application  (`core.application`)
The tenant-of-record that owns intakes. Fields written by this slice: `name` (unique, non-blank),
`description?`, `created_by_actor_id`, `created_role_code`. Server-set: `application_id` (uuidv7),
`created_at`, `updated_at`.

### intake  (`core.intake`)
A governed use-case under an application.
- FKs: `application_id → application`.
- Classification (nullable, set via /classification): `ai_risk_tier_code → reference.ai_risk_tier`,
  `naic_materiality_code → reference.naic_materiality`, `materiality_tier_code → reference.materiality_tier`.
- `intake_status_code → reference.intake_status` (default `proposed`) — **mutable; every change
  appended to `audit.status_transition`** (D4).
- `title`, `description?`; attribution `created_by_actor_id`, `created_role_code`.

### intake_requirement  (`core.intake_requirement`)
A typed requirement on an intake.
- FK: `intake_id → intake` (cascade).
- `requirement_kind_code → reference.requirement_kind`,
  `requirement_status_code → reference.requirement_status` (default `draft`).
- `title`, `body`; `embedding vector(384)` — **left null this slice** (D-INT-6).
- attribution `created_by_actor_id`, `created_role_code`.

## Audit (Tier-2, `audit`)

### status_transition  (`audit.status_transition`)
The single shared append-only log of every mutable `*_status_code` change (D4). This slice writes
one row per intake status change: `entity_type='intake'`, `entity_id = intake_id`,
`status_field='intake_status_code'`, `from_code`, `to_code`, `actor_id`, `acting_role_code`, `reason?`.

## Reference vocabularies (read-only, seeded)

`reference.intake_status`, `reference.ai_risk_tier`, `reference.naic_materiality`,
`reference.materiality_tier`, `reference.requirement_kind`, `reference.requirement_status`. The
API validates `*_code` inputs via these FKs (D-INT-7).

## Relationships

```
application 1───* intake 1───* intake_requirement
                   │
                   └── status change ──> audit.status_transition (entity_type='intake')
```

## Validation rules (from the spec + schema)

- `application.name` non-blank, unique (DB CHECK + UNIQUE).
- `intake.*_code` and `requirement_*_code` must exist in their reference table (DB FK → 400).
- Status change target must be a valid `reference.intake_status` code; **legal-transition gating
  is deferred** (D-INT-2).
- Every create/update records `actor_id + acting_role` server-side (D6; never client-supplied — FR-018).

## State (intake_status)

Current state is the row's `intake_status_code`; the **history** is the ordered
`audit.status_transition` rows for that intake. This slice does not constrain which transitions
are legal (D-INT-2) — that state-machine is a later slice.
