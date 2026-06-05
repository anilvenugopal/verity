# Phase 0 — Research & Decisions: Intake Assessment slice (capture + tier + ceiling)

Decisions specific to this slice. The stack/storage are fixed; the compliance metamodel is
unseeded, so obligation resolution is out of scope (see plan.md Scope).

## D-ASM-1 — Reuse `intake_impact_assessment` (jsonb + SCD-2); no new table
- **Decision**: the four-tab questionnaire is stored in the existing `core.intake_impact_assessment`
  — `assessment jsonb` holds the structured answers; each submit writes a **new revision** (closes
  the prior open SCD-2 window: set its `valid_to = now()`, insert `revision = max+1` with
  `valid_to = '2099-12-31'`). Reads use `core.intake_impact_assessment_current`.
- **Rationale**: the entity already exists and is designed for exactly this (D4 history-keeping);
  `(intake_id, revision)` is UNIQUE; no schema growth for the assessment itself.
- **Alternatives**: a new per-question table (rejected — premature relational modeling before the
  obligation-resolution slice needs queryable answers; jsonb is the documented shape).

## D-ASM-2 — Boundary-validated jsonb (Pydantic shape; stored opaque)
- **Decision**: the API validates the 4-tab answer shape with Pydantic models (enumerated choices
  per FR-AS-002/003), then stores it as `jsonb`. The DB does not constrain the answer structure.
- **Rationale**: keeps the answer schema evolvable while still rejecting malformed input at the
  boundary; the tier rules read named fields off the validated model.
- **Alternatives**: a JSON-schema CHECK in the DB (rejected — duplicates the Pydantic contract,
  brittle as questions evolve).

## D-ASM-3 — Inherent tier computed from answers; set via the existing intake classify path
- **Decision**: the AI-Decision-Impact answers drive a deterministic rules function →
  `ai_risk_tier` (`minimal`|`limited`|`high`|`unacceptable`) + `naic_materiality`
  (`material`|`non_material`). The computed values are written to the intake via the **existing**
  `intake.service.classify_intake` (Slice-1) — gated here by `edit_impact_assessment` rather than
  `reclassify_risk`. The tier is **inherent** (FR-AS-008) — not lowered by anything in this slice.
- **Rationale**: one source of truth for the intake's `*_code` columns; reuse, no duplication.
- **Alternatives**: a separate assessment-owned tier column (rejected — the intake already owns
  `ai_risk_tier_code`).
- **⚠️ Policy (R1)**: the actual answer→tier mapping is a **governance policy artifact**, documented
  in [rules-mapping.md](rules-mapping.md) and authored as a conservative draft — it **requires
  compliance/domain-expert review before production use**. The tier-driving answers are strict enums
  (A1) so an unexpected value 422s rather than silently down-tiering. Note the seeded
  `reference.data_classification` codes are tier-prefixed (`tier1_public`…`tier4_pii_restricted`),
  not the shorthand used in prose (D1).

## D-ASM-4 — `unacceptable` auto-rejects the intake (audited), reusing change_status
- **Decision**: a computed `unacceptable` tier triggers the FR-IN-004 safety behavior — the intake
  is auto-rejected (`intake_status_code = 'rejected'`) with the canonical note, in one transaction
  that also appends `audit.status_transition`, via the **existing** `intake.service.change_status`.
- **Rationale**: closes the intake-slice FR-IN-004 auto-reject deferral; the audited one-txn path
  already exists (D-INT-1).
- **Alternatives**: leave it to a human (rejected — prohibited use under EU-AI-Act framing is a
  hard stop, not a discretionary call).

## D-ASM-5 — Intake data classification + ceiling (closes T034)
- **Decision**: add `core.intake.data_classification_code` (FK `reference.data_classification`,
  NULL until the Data tab is completed). On capture, enforce the **application ceiling**: the
  intake's classification rank MUST NOT exceed the app's `data_classification_code` (FR-IN-018),
  and `processes_pii = true` in the Data tab implies a classification ≥ `tier3_confidential`. A
  violation is a 400.
- **Rationale**: the Data tab is where the intake's sensitivity is first declared; this is the
  natural home for the ceiling check deferred from Slice 2 (T034).
- **Alternatives**: enforce only at intake create (rejected — the classification is set by the
  assessment, after create).

## D-ASM-6 — Captured-but-not-resolved tabs are still stored
- **Decision**: the **Security & Access** answers (sources/targets/tools) and any **Data**-tab
  fields beyond classification are **captured** in the `assessment` jsonb even though their
  downstream machinery (approvable access records, ITSM export, obligation resolution, mitigations)
  is deferred. Nothing is dropped — the answers persist for the later slices to consume.
- **Rationale**: forward-compatibility (Principle VI — never silently drop); the later slices read
  the captured answers rather than re-asking.

## Error model (slice)
- `401/403` → `AuthError`. `404` → unknown intake / no assessment yet.
- `400` → classification exceeds the app ceiling; `processes_pii` without ≥ confidential.
- `422` → Pydantic answer-shape validation.
- `409` → reserved (e.g. assessing a terminal intake) — minimal in this slice.
