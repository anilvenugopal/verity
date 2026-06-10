---
description: "Task list — Intake Approval slice (001-verity-governance-service)"
---

# Tasks: Intake Approval slice — verity-governance-service

**Input**: [plan.md](plan.md), [research.md](research.md) (D-IAP-1…5), [data-model.md](data-model.md),
[contracts/intake-approval-openapi.yaml](contracts/intake-approval-openapi.yaml), [quickstart.md](quickstart.md).

**Tests**: INCLUDED — the plan requires PG18 end-to-end tests per story.

**Slice note**: Slice 4. Slices 1–3 (Intake CRUD, Application Onboarding, Intake Assessment) shipped;
their task lists are in git history. **No new tables** — reuses the Slice-2 approval primitive
(generalizing `open_request` for `target_intake_id`), the Slice-3 computed tier, and the Slice-1
audited `change_status`.

## Format: `[ID] [P?] [Story] Description`
- **[P]**: parallelizable (different files, no incomplete-task dependency)
- Paths are repo-relative; hub component is `hub/` (package `verity.hub`).

---

## Phase 1: Setup

- [X] T001 Hub + migrate/reset + PG18 testcontainer + Slice-1/2/3 modules (done)
- [X] T002 [P] Create package skeleton `hub/src/verity/hub/intake_approval/__init__.py` + test dir `hub/tests/verity/hub/intake_approval/`

## Phase 2: Foundational — generalize the approval primitive (BLOCKS all stories)

- [X] T003 Generalize `open_request` (bind `target_intake_id` alongside `target_application_id`, one null) and `get_request` (RETURNING/SELECT both target columns) — `hub/db/queries/approval.sql`
- [X] T004 Generalize `approval.service.open_request` (accept `target_intake_id` + `target_application_id`, default None); add `target_intake_id` to `approval.models.ApprovalRequest`; update the onboarding caller to pass `target_intake_id=None` — `hub/src/verity/hub/approval/{service,models}.py`, `hub/src/verity/hub/application/service.py`
- [X] T005 Make the approval router a **kind-dispatcher**: `GET /approvals/{id}` and `POST /approvals/{id}/signoff` route by `request_kind_code` (`application_onboarding` → `application.service`; `intake` → `intake_approval.service`) — `hub/src/verity/hub/approval/router.py`
- [X] T006 **Regression checkpoint**: full hub suite green on PG18 (onboarding approval still works after the generalization)

**Checkpoint**: the primitive is intake-capable and onboarding is unbroken.

---

## Phase 3: User Story 1 (P1) — Submit an intake for approval

**Goal**: an assessed intake (with a tier) is submitted, opening a `kind=intake` approval with the tier-based quorum.
**Independent test**: a `high` intake → approval opened, `required_roles` = the 5 (FR-IN-005); a `minimal` intake → `[business_owner]`; an unassessed intake (no `ai_risk_tier_code`) → 400; a viewer → 403.

- [X] T007 [P] [US1] Raw SQL — `hub/db/queries/intake_approval.sql` (`get_intake_tier_status`, `has_open_intake_approval`)
- [X] T008 [P] [US1] Quorum map + models — `hub/src/verity/hub/intake_approval/{models,service}.py`: `_INTAKE_QUORUM` (FR-IN-005); reuse `approval.models.ApprovalRequest`
- [X] T009 [US1] Service `submit_for_approval` — require `ai_risk_tier_code` (else 400); reject a terminal intake + a duplicate open approval (409); open the `kind=intake` request (`target_intake_id`); return the view with computed `required_roles` — `hub/src/verity/hub/intake_approval/service.py`
- [X] T010 [US1] Router `POST /intakes/{id}/submit` (gated `edit_intake`; 400 no-tier, 409 terminal/duplicate, 404 missing) + wire `app.include_router` — `hub/src/verity/hub/intake_approval/router.py`, `hub/src/verity/hub/app.py`
- [X] T011 [US1] e2e test — `hub/tests/verity/hub/intake_approval/test_intake_approval.py`: high → 5 roles; minimal → `[business_owner]`; no-tier → 400; viewer → 403

**Checkpoint**: US1 independently runnable + tested.

---

## Phase 4: User Story 2 (P2) — Quorum sign-off → approve

**Goal**: the tier quorum signs off; a satisfied quorum moves the intake to `approved` (audited).
**Independent test**: a `minimal` intake (quorum `[business_owner]`) → a `business_owner` signs `approved` → intake `approved` + one `audit.status_transition` row; a `high` intake with a partial quorum → still `pending`; a signer holding no required role → 403; any `rejected` sign-off → request `rejected`.

- [X] T012 [US2] Service `sign_off` — pick a required-role slot the signer holds (403 if none / already filled); record the sign-off; resolve (any `rejected` → request `rejected`; **every** required role `approved` → intake `approved` via the audited `intake.service.change_status`, D-INT-1); `get_request_view` computes `required_roles` from the tier — `hub/src/verity/hub/intake_approval/service.py`
- [X] T013 [US2] Wire the intake branch of the approval-router dispatch (`get`/`signoff`) to `intake_approval.service`; map `IntakeApprovalConflict` → 409, `AuthError` → 403 — `hub/src/verity/hub/approval/router.py`
- [X] T014 [US2] e2e test — `test_intake_approval.py`: minimal → BO signs → intake `approved` + one audit row; high partial → `pending`; non-required signer → 403; a `rejected` sign-off → request `rejected`

---

## Phase 5: User Story 3 (P3) — Submit/sign-off guards

**Goal**: prevent invalid approval state (duplicate approvals, terminal intakes, double-signing a role slot).
**Independent test**: double-submit → 409; submitting a `rejected` intake → 409; a signer signing twice for the same role slot → 409.

- [X] T015 [US3] e2e guard tests — `test_intake_approval.py`: double-submit → 409; terminal (`rejected`) intake submit → 409; the same role slot signed twice → 409 (the guards themselves live in T009/T012)

---

## Phase 6: Polish & cross-cutting

- [X] T016 [P] Dev console read-only queries (open intake approvals + tier/quorum + status) — `tools/src/verity/dev/catalog.py`
- [X] T017 [P] Refresh `quickstart.md` if endpoint shapes shifted; confirm acceptance mapping
- [X] T018 Full hub suite green (`pytest -q`) + `ruff check` clean + `migrate`/`reset` idempotent on PG18

---

## Dependencies & order

- **Phase 2 blocks Phase 3+** (the `open_request` generalization + kind-dispatch).
- **US1 → US2 → US3**: US2 resolves the approval US1 opens; US3 hardens both. US1 is the MVP.
- **Cross-slice reuse (not re-built)**: the Slice-2 approval primitive (`approval.service`), `intake.service.change_status` (US2 resolve), the Slice-3 `ai_risk_tier_code`.

## Parallel opportunities

- Phase 3: T007 (SQL) + T008 (models/quorum) in parallel → T009 → T010 → T011.
- Phase 2 is mostly sequential (the generalization is a chain: SQL → service/models → router → regression).

## Implementation strategy

- **MVP = US1** (submit → open the tier-quorum approval): the smallest tested increment.
- Then US2 (quorum sign-off → approve) and US3 (guards). Run the **Phase-2 regression** before the
  stories — generalizing `open_request` must not break onboarding approval.

## Deferred (NOT in this slice — recorded)

**Re-approval on reclassification / business change** (FR-IN-013 — `risk_reclassification` /
`business_change` kinds + impacted-asset selection + draft-fork); **asset linking / promotion gate**
(FR-IN-009 — "an approved intake unlocks asset promotion"); the **assessment-justification
completeness gate** beyond "a tier exists" (FR-AS-010).

Recorded from /speckit.analyze (not silent):
- **G2 — `withdraw_approval`**: the `withdraw_approval` action exists in the matrix but has no
  route — an open approval can't be cancelled/withdrawn. Lands with the reclassification slice
  (FR-IN-013) or as a small dedicated `POST /approvals/{id}/withdraw`.

Remediated in this slice (analyze): **G1** submitter≠signer separation of duty (self-approval → 403);
**U1** empty-quorum tier rejected at submit; **I2** submit advances the intake `proposed → in_review`
(audited); **I1** FR-IN-001 text reconciled to the submit/tier-quorum model.
