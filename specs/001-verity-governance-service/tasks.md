---
description: "Task list — Intake Assessment slice (001-verity-governance-service)"
---

# Tasks: Intake Assessment slice — verity-governance-service

**Input**: [plan.md](plan.md), [research.md](research.md) (D-ASM-1…6), [data-model.md](data-model.md),
[contracts/assessment-openapi.yaml](contracts/assessment-openapi.yaml), [quickstart.md](quickstart.md).

**Tests**: INCLUDED — the plan requires PG18 end-to-end tests per story.

**Slice note**: Slice 3 of this feature. Slice 1 (Intake CRUD) + Slice 2 (Application Onboarding)
shipped; their task lists are in git history. **Scope reality:** the obligation-set *resolution*
(FR-AS-001 / FR-IN-014) is **deferred** — the compliance metamodel is entirely unseeded. This
slice builds **capture + inherent tier + ceiling**, storing answers forward-compatibly.

## Format: `[ID] [P?] [Story] Description`
- **[P]**: parallelizable (different files, no incomplete-task dependency)
- Paths are repo-relative; hub component is `hub/` (package `verity.hub`).

---

## Phase 1: Setup

- [X] T001 Hub component + migrate/reset + PG18 testcontainer + Slice-1/2 modules (done)
- [ ] T002 [P] Create package skeleton `hub/src/verity/hub/assessment/__init__.py` + test dir `hub/tests/verity/hub/assessment/`

## Phase 2: Foundational — schema growth (BLOCKS all stories; review DDL first — Principle II)

- [ ] T003 ALTER `core.intake`: add `data_classification_code text` (FK `reference.data_classification`, NULL) + catalog comment (the intake's actual sensitivity; ≤ app ceiling) — `specs/schema/core/intake.sql`
- [ ] T004 Update `specs/schema/DATA-MODEL.md` / `TABLE-INDEX.md` for the new intake column
- [ ] T005 **Review checkpoint** (Principle II): `migrate` + `reset` on PG18; the existing 21-test suite stays green; new column loads

**Checkpoint**: schema grown + reviewed before any story work.

---

## Phase 3: User Story 1 (P1) — Capture the assessment

**Goal**: submit/read the four-tab questionnaire as a versioned record (SCD-2) on `intake_impact_assessment`.
**Independent test**: PUT the 4-tab body → revision 1 stored (open window); PUT again → revision 2 (revision 1 closed, `valid_to` set); GET returns the current revision; `GET .../revisions` lists both; a viewer-only principal is denied (403) on PUT, allowed on GET.

- [ ] T006 [P] [US1] Raw SQL — `hub/db/queries/assessment.sql` (`next_revision`, `get_current_assessment`, `close_current_assessment`, `insert_assessment_revision`, `list_revisions`)
- [ ] T007 [P] [US1] Pydantic models — `hub/src/verity/hub/assessment/models.py` (`AssessmentInput` with the 4 tabs + enumerated choices per FR-AS-002/003; `AssessmentView`; `RevisionMeta`)
- [ ] T008 [US1] Service capture — `hub/src/verity/hub/assessment/service.py`: one transaction (next revision → close current → insert new revision; store answers as `jsonb`); `get_current`; `list_revisions`; attribution server-set (D6)
- [ ] T009 [US1] Router — `hub/src/verity/hub/assessment/router.py`: `PUT/GET /intakes/{id}/assessment`, `GET /intakes/{id}/assessment/revisions` (gated `edit_impact_assessment` / `view`; 404 on unknown intake); wire `app.include_router` in `hub/src/verity/hub/app.py`
- [ ] T010 [US1] e2e test (PG18) — `hub/tests/verity/hub/assessment/test_assessment.py`: submit→rev1; resubmit→rev2 (rev1 closed); GET current; revisions list; viewer 403 on PUT / 200 on GET

**Checkpoint**: US1 independently runnable + tested.

---

## Phase 4: User Story 2 (P2) — Inherent tier + auto-reject

**Goal**: the AI-Decision-Impact answers compute the intake's inherent `ai_risk_tier` + `naic_materiality`; `unacceptable` auto-rejects the intake (audited).
**Independent test**: high-risk answers (autonomous + consumer + denial/discriminatory in an insurance domain) → `intake.ai_risk_tier_code='high'`; an `unacceptable` pattern → `intake.intake_status_code='rejected'` + exactly one `audit.status_transition` row.

- [ ] T011 [P] [US2] Tier rules — `hub/src/verity/hub/assessment/rules.py`: deterministic `compute_tier(ai_decision_impact) -> (ai_risk_tier_code, naic_materiality_code)` per EU-AI-Act framing (inherent — FR-AS-002/008); document the mapping
- [ ] T012 [US2] Service: on capture, set the intake tier via the existing `intake.service.classify_intake`; if `ai_risk_tier_code == 'unacceptable'` → auto-reject via the existing audited `intake.service.change_status` (one txn, D-INT-1) — `hub/src/verity/hub/assessment/service.py`
- [ ] T013 [US2] Populate `AssessmentView.computed` (tier / materiality / `intake_status_code` / `auto_rejected`) — `hub/src/verity/hub/assessment/{models,service}.py`
- [ ] T014 [US2] e2e test — `test_assessment.py`: high-risk → `ai_risk_tier='high'`; unacceptable → intake `rejected` + one audit row (from/to/actor)

---

## Phase 5: User Story 3 (P3) — Data classification + ceiling (closes T034)

**Goal**: the Data tab sets `intake.data_classification_code`, rejected if it exceeds the application ceiling or violates the PII rule.
**Independent test**: a within-ceiling classification persists on the intake; one exceeding the app ceiling → 400; `pii_presence != none` without ≥ `tier3_confidential` → 400.

- [ ] T015 [P] [US3] Raw SQL — `assessment.sql` (`set_intake_classification`, `get_intake_app_ceiling` joining `core.application`)
- [ ] T016 [US3] Service: on capture, set `intake.data_classification_code` from the Data tab; enforce rank ≤ app ceiling and `pii_presence != none ⇒ ≥ tier3_confidential` (reuse the rank map; ValueError → 400) — `hub/src/verity/hub/assessment/service.py`
- [ ] T017 [US3] e2e test — `test_assessment.py`: within-ceiling persists; over-ceiling → 400; PII-without-confidential → 400

---

## Phase 6: Polish & cross-cutting

- [ ] T018 [P] Dev console read-only queries (current assessment per intake; computed tier; revision count) — `tools/src/verity/dev/catalog.py`
- [ ] T019 [P] Refresh `quickstart.md` if endpoint shapes shifted; confirm acceptance mapping
- [ ] T020 Full hub suite green (`pytest -q`) + `ruff check` clean + `migrate`/`reset` idempotent on PG18

---

## Dependencies & order

- **Phase 2 blocks Phase 3+** (the `intake.data_classification_code` column + review).
- **US1 → US2 → US3**: US2 computes the tier from US1's captured answers; US3 enforces the ceiling on the same capture path. US1 is the MVP.
- **Cross-slice reuse (not re-built)**: `intake.service.classify_intake` (US2 tier), `intake.service.change_status` (US2 auto-reject), the application rank map / ceiling (US3).

## Parallel opportunities

- Phase 3: T006 (SQL) + T007 (models) in parallel → T008 → T009 → T010.
- T011 (rules) is independent of the SQL/models and can be written in parallel with Phase-3 tasks.

## Implementation strategy

- **MVP = US1** (capture the versioned assessment): the smallest tested increment.
- Then US2 (inherent tier + auto-reject) and US3 (classification + ceiling). Review the Phase-2 column add before wiring services (Principle II).

## Deferred (NOT in this slice — recorded; blocked on prerequisites)

**Obligation resolution** (FR-AS-001 mapping → `intake_obligation`; unseeded compliance metamodel —
dedicated content slice); **Security & Access approvable records + ITSM export** (FR-AS-004/005);
**mitigations / risk-treatment + `approve_exception`** (FR-AS-006/007); the **Risk & Obligations**
tab's obligation portion (FR-AS-009). The Security & Access answers are **captured** in the
assessment `jsonb` (US1) for those later slices.
