# Phase 0 — Research & Decisions: Intake slice

No `NEEDS CLARIFICATION` remained in the Technical Context (the stack, storage, and schema are
fixed by the constitution + ADRs). The decisions below resolve the design choices specific to
this slice.

## D-INT-1 — Status change is one transaction: row update + audit insert
- **Decision**: `POST /intakes/{id}/status` reads the current `intake_status_code`, then in a
  **single transaction** `UPDATE core.intake SET intake_status_code = :to` and
  `INSERT audit.status_transition(entity_type='intake', entity_id, status_field='intake_status_code',
  from_code, to_code, actor_id, acting_role_code, reason)`.
- **Rationale**: the mutable status and its append-only history must never diverge (D4). One
  txn guarantees the audit row exists iff the status moved.
- **Alternatives**: a DB trigger writing the audit row (rejected — hides the write, harder to
  attribute the acting role); app-level two-step without a txn (rejected — divergence on partial
  failure).

## D-INT-2 — No status state-machine this slice (accept any valid code)
- **Decision**: the endpoint accepts any value present in `reference.intake_status`; the FK
  enforces validity. Which transitions are *legal* (e.g. proposed→triaged) is **deferred**.
- **Rationale**: the intake lifecycle state-machine is a governance policy that deserves its own
  spec; gating on the vocab keeps the slice honest without inventing rules.
- **Alternatives**: hard-code a transition table now (rejected — premature, unspecced).

## D-INT-3 — Attribution via AuthContext.acting_role
- **Decision**: writes record `created_by_actor_id = principal.actor_id` and
  `created_role_code` / `acting_role_code = ctx.acting_role` — the role the principal acted under
  (a held role that authorized the action, resolved by `acting_role_for`).
- **Rationale**: D6 attribution = actor + acting capacity; FR-018 forbids self-asserted roles, so
  the role is server-resolved from the gate, never the request body.
- **Alternatives**: store the full role set (rejected — the schema records a single acting role);
  client-supplied role (rejected — FR-018).

## D-INT-4 — `onboard_application` action (provisional matrix cell)
- **Decision**: application creation is gated by a new action `onboard_application`, allowed to
  `business_owner`, `ai_governance`, `security`. Reads use `view`.
- **Rationale**: every route must map to an action (FR-029 default-deny); application onboarding
  had no cell. Marked **provisional** until reconciled against the v1 action set.
- **Alternatives**: reuse `create_intake` (rejected — different authority); leave ungated
  (rejected — FR-029 would deny it anyway).

## D-INT-5 — Row→model mapping via dict_row, not `to_jsonb`
- **Decision**: the pool uses `row_factory=dict_row`; queries `RETURNING` the needed columns;
  handlers build Pydantic models with `Model(**row)`.
- **Rationale**: clean, explicit column→field mapping with no positional fragility; avoids the
  `to_jsonb` wrinkle with the `vector` column on `intake_requirement`.
- **Alternatives**: `to_jsonb(t.*)` (rejected — vector serialization + opaque columns); positional
  tuples (rejected — fragile).

## D-INT-6 — Requirement embedding left null this slice
- **Decision**: `POST /intakes/{id}/requirements` inserts `title`/`body`/`kind` and leaves
  `embedding` null. Embedding generation + semantic dedup is **deferred**.
- **Rationale**: embeddings need the embedding runtime (`embedding_config`) and a dedup policy —
  out of scope; the column is nullable so this is forward-compatible.

## D-INT-7 — Reference-code validation by FK, surfaced as 4xx
- **Decision**: invalid `*_code` values (risk tier, materiality, status, requirement kind) are
  rejected by the existing FKs; the API maps the DB integrity error to a 400/422 with the bad
  field, not a 500.
- **Rationale**: the DB is the source of truth for the vocab; duplicating the allowed sets in the
  app would drift. One source, surfaced cleanly.

## Error model (slice)
- `401/403` → `AuthError` (unauthenticated / action denied), non-leaking JSON `{code, detail,
  request_id}`.
- `404` → unknown application/intake/requirement id.
- `422` → Pydantic request validation; `400` → invalid reference code (FK violation), with field.
- `409` → reserved for illegal status transitions once D-INT-2's state-machine lands.
