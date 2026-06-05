# Implementation Plan — Intake Assessment slice (capture + tier + ceiling)

**Branch**: `001-verity-governance-service` · **Spec**: [spec.md](spec.md) (FR-AS-001…010, FR-IN-004/017/018, FR-RP-010)
**Slice**: the structured intake assessment — capture the questionnaire, compute the inherent risk tier, and enforce the data-classification ceiling.

> **Slice history (one feature, sequential slices):**
> - **Slice 1 — Intake CRUD (shipped):** `8780d24`, `fc2dd8d`.
> - **Slice 2 — Application Onboarding (shipped):** `4252d88`, `f222d71`, `7d0003e`, `8229063` (perimeter + governed approval).
> - **Slice 3 — Intake Assessment (this plan):** the assessment questionnaire + inherent-tier computation + the intake data-classification ceiling (closes the deferred T034). Prior slices' plan artifacts are in git history.

## Summary

The intake assessment is the structured front-end that drives risk classification. This slice builds the **buildable core**: a four-tab questionnaire stored as a versioned `jsonb` on the existing `core.intake_impact_assessment` (SCD-2 revisions), whose **AI-Decision-Impact** answers compute the intake's **inherent `ai_risk_tier` + `naic_materiality`** (auto-rejecting an `unacceptable` use case), and whose **Data** tab sets the intake's **`data_classification`** — enforced against the application's onboarding **ceiling** (FR-IN-018, closing T034).

## ⚠️ Scope reality (confirmed with the product owner)

The assessment's *headline* outcome — resolving answers → the **obligation set** (FR-AS-001 / FR-IN-014) — is **NOT buildable in this slice**: the compliance metamodel (`canonical_requirement`, `regulatory_provision`, `control`, `evidence_specification`, `requirement_tier`, `intake_obligation`) is **entirely unseeded** (0 rows). Authoring that content is a large, dedicated governance-content effort. This slice captures the answers **forward-compatibly** (so resolution wires in later) but does not resolve obligations.

## Technical Context

- **Stack:** unchanged (Python 3.12 · FastAPI · psycopg v3 async · aiosql raw SQL · Pydantic v2 · PG18). New module `verity.hub.assessment`. Tests mirror the package.
- **Data layer:** **reuse** `core.intake_impact_assessment` (jsonb `assessment` + SCD-2 `valid_from`/`valid_to` + `(intake_id, revision)` UNIQUE) and its `_current` view — they already exist. **One schema add:** `core.intake.data_classification_code`.
- **Cross-slice reuse:** `intake.service.classify_intake` (set the computed tier/materiality), `intake.service.change_status` (one-txn audited auto-reject), the application **ceiling** (`application.data_classification_code` + the rank map from `application.service`).
- **NEEDS CLARIFICATION:** none blocking — D-ASM-1…6 in research.md.

## Constitution Check

| Principle | Gate | Status |
|---|---|---|
| I — Spec precedes implementation | FR-AS-* specced; scope confirmed | ✅ PASS |
| II — Schema is the hardened foundation | One reviewed column add (`intake.data_classification_code`); reuses the existing assessment entity | ✅ PASS |
| IV — API-only governance boundary | Gated `edit_impact_assessment` / `view`; attribution server-resolved (D6) | ✅ PASS |
| VI — Slice-first, parity committed | Obligation resolution + access records + mitigations deferred **with reason** (unseeded metamodel) — never silent | ✅ PASS |
| VIII — Continuous control-and-evidence compliance | Assessment captured + tier computed here; obligation/evidence resolution is the dedicated content slice | ✅ PASS (partial-by-design, recorded) |

No violations.

## Scope

**In scope**
- Schema: `core.intake.data_classification_code` (FK `reference.data_classification`, NULL).
- The 4-tab assessment captured as structured `jsonb` on `intake_impact_assessment`, SCD-2 revisions.
- Inherent **risk-tier + materiality** computation from the AI-Decision-Impact answers (FR-AS-002/008); `unacceptable` → audited auto-reject (closes the intake-slice FR-IN-004 auto-reject deferral).
- **Data-classification ceiling** enforcement (intake ≤ app; `processes_pii` ⇒ ≥ confidential) — closes T034.
- The Data/Security answers are **captured** (stored) even where their downstream machinery is deferred.

**Out of scope (deferred — recorded; blocked on prerequisites)**
- **Obligation resolution** (FR-AS-001 mapping → `intake_obligation`) — blocked on the unseeded compliance metamodel; a dedicated content slice.
- **Security & Access approvable records + ITSM export** (FR-AS-004/005) — a focused sub-capability.
- **Mitigations / risk-treatment + `approve_exception`** (FR-AS-006/007) — needs the `approve_exception` action + evidence linkage.
- **Risk & Obligations** tab's obligation portion (FR-AS-009) — depends on resolution; the tier/materiality portion is in scope.

## User-story decomposition (drives /speckit.tasks)

- **Foundational** — `intake.data_classification_code` column (reviewed); `verity.hub.assessment` skeleton.
- **US1 (P1) — Capture the assessment:** `PUT/GET /intakes/{id}/assessment` — the 4-tab structured body stored as a new SCD-2 revision; GET returns the current revision. *Independent test:* submit → revision 1; resubmit → revision 2 (old closed); GET returns current + history count; viewer denied on PUT.
- **US2 (P2) — Compute the inherent tier:** the AI-Decision-Impact answers compute `ai_risk_tier` + `naic_materiality` (set on the intake); `unacceptable` → audited auto-reject. *Independent test:* high-risk answers → `intake.ai_risk_tier='high'`; `unacceptable` → intake `rejected` + one `audit.status_transition` row.
- **US3 (P3) — Data classification + ceiling:** the Data tab sets `intake.data_classification_code`, rejected if it exceeds the app ceiling (or `processes_pii` without ≥ confidential). *Independent test:* within-ceiling persists; over-ceiling → 400.

## Project structure (additions)

```
hub/
  db/queries/assessment.sql              # upsert revision, get current, list revisions, set intake classification
  src/verity/hub/assessment/{models,service,router}.py   # the 4-tab models, tier rules, ceiling check
  tests/verity/hub/assessment/test_assessment.py         # PG18 e2e
specs/schema/core/intake.sql             # ALTER: + data_classification_code
```

## Complexity Tracking

| Item | Note |
|---|---|
| Headline outcome (obligations) unbuildable | Metamodel unseeded; captured forward-compatibly, resolution deferred to a content slice (recorded). |
| Reuse of intake classify/status | The computed tier sets the intake via the existing `classify_intake`; `unacceptable` auto-reject via the existing audited `change_status`. No duplication. |
| Assessment as jsonb | The questionnaire shape is Pydantic-validated at the boundary, stored as `jsonb` (the entity is designed for it); queryable structuring is deferred until obligation resolution needs it. |

## Phases

- **Phase 0 — research.md:** D-ASM-1…6.
- **Phase 1 — data-model.md + contracts/assessment-openapi.yaml + quickstart.md.**
- **Phase 2 — /speckit.tasks.**
