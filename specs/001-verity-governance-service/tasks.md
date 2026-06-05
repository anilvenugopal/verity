---
description: "Task list — Application Onboarding slice (001-verity-governance-service)"
---

# Tasks: Application Onboarding slice — verity-governance-service

**Input**: [plan.md](plan.md), [research.md](research.md) (D-ONB-1…7), [data-model.md](data-model.md),
[contracts/onboarding-openapi.yaml](contracts/onboarding-openapi.yaml), [quickstart.md](quickstart.md).

**Tests**: INCLUDED — the plan requires PG18 end-to-end tests per story.

**Slice note**: Slice 2 of this feature. The **Intake CRUD slice (US1–US4)** shipped (commits
`8780d24`, `fc2dd8d`; its task list is in git at `32d542d`). This slice **supersedes** the thin
Slice-1 instant `POST /applications` with a governed propose→approve flow.

## Format: `[ID] [P?] [Story] Description`
- **[P]**: parallelizable (different files, no incomplete-task dependency)
- Paths are repo-relative; hub component is `hub/` (package `verity.hub`).

---

## Phase 1: Setup

- [X] T001 Hub component + migrate/reset + PG18 testcontainer + auth foundation (done, Slice 1)
- [X] T002 [P] Create package skeletons `hub/src/verity/hub/application/__init__.py` and `hub/src/verity/hub/approval/__init__.py`
- [X] T003 [P] Create test dirs `hub/tests/verity/hub/application/` and `hub/tests/verity/hub/approval/`

## Phase 2: Foundational — schema growth (BLOCKS all stories; review DDL first — Principle II)

- [X] T004 [P] ALTER `core.application`: add `code` (TLA — `UNIQUE`, `CHECK (code ~ '^[A-Z]{3}$')`), `application_status_code` (FK `reference.application_status`, default `'pending'`), `data_classification_code` (FK `reference.data_classification`), `line_of_business_code` (FK `reference.line_of_business`, NULL), `business_owner_actor_id` (FK `core.actor`, NOT NULL), `affects_consumers`/`processes_pii`/`consumer_facing` (boolean NOT NULL) — `specs/schema/core/application.sql`
- [X] T005 [P] ALTER `core.approval_request`: add `target_application_id` (uuid NULL, FK `core.application`) — `specs/schema/core/approval_request.sql`
- [X] T006 [P] NEW `reference.application_status` (`pending`/`active`/`suspended`/`retired`) + seed — `specs/schema/reference/application_status.sql`, `specs/schema/seed/reference_seed.sql`
- [X] T007 [P] NEW `reference.jurisdiction` (US states + `eu`/`uk`/…) + seed — `specs/schema/reference/jurisdiction.sql`, seed
- [X] T008 [P] NEW `reference.line_of_business` (`pc`/`life`/`health`/`annuities`/`commercial`/`reinsurance`/`other`) + seed — `specs/schema/reference/line_of_business.sql`, seed
- [X] T009 [P] NEW `core.application_regulatory_framework` join (`application_id`, `framework_code`) — `specs/schema/core/application_regulatory_framework.sql`
- [X] T010 [P] NEW `core.application_governance_domain` join (`application_id`, `governance_domain_code`) — `specs/schema/core/application_governance_domain.sql`
- [X] T011 [P] NEW `core.application_jurisdiction` join (`application_id`, `jurisdiction_code`) — `specs/schema/core/application_jurisdiction.sql`
- [X] T012 Verify/repair `reference.data_classification` seed to `{public, internal, confidential, pii_restricted}` (D-ONB-3) — `specs/schema/seed/reference_seed.sql`
- [X] T013 Rename `app_team_role` seed `app_demo_*` → `app_{owner,lead,dev,sre,ops}` + fix references; record the v1→v2 disposition (D-ONB-6) — `specs/schema/reference/app_team_role.sql`, seed, `specs/schema/DATA-MODEL.md`
- [X] T014 Seed/validate the `application_onboarding` approval-request kind (D-ONB-7)
- [X] T015 Update `data-model.md` (add `business_owner_actor_id`) + `specs/schema/DATA-MODEL.md` / `TABLE-INDEX.md` for the new objects
- [~] T016 Migration 0002 — SKIPPED (canonical-only strategy; dev is reset-based; no numbered migration this slice)
- [X] T017 **Review checkpoint** (Principle II): run `migrate` + `reset` on PG18; the existing 13-test suite stays green; new schema loads + seeds idempotent

**Checkpoint**: schema grown + reviewed; all existing tests pass before any story work.

---

## Phase 3: User Story 1 (P1) — Propose an application  🎯 MVP

**Goal**: propose creates a `pending` application capturing identity + ownership + compliance perimeter; reads work; action-gated.
**Independent test**: an `onboard_application`-authorized author proposes an app → it persists `pending` with a unique well-formed TLA, the perimeter rows (≥1 framework/domain/jurisdiction), the three attestations, the business owner; a viewer is denied (403) on propose, allowed on GET; a bad perimeter cardinality / missing attestation → 400; a duplicate TLA → 409.

- [X] T018 [P] [US1] Raw SQL propose/read — `hub/db/queries/application_onboarding.sql` (`propose_application`, `get_application`, `list_applications`)
- [X] T019 [P] [US1] Raw SQL perimeter — `hub/db/queries/application_perimeter.sql` (insert + list frameworks / domains / jurisdictions)
- [X] T020 [P] [US1] Pydantic models `ApplicationPropose` / `Application` (fields mirror schema; perimeter as code arrays) — `hub/src/verity/hub/application/models.py`
- [X] T021 [US1] Service `propose` — insert `pending` app + `business_owner_actor_id` + perimeter rows + initial app-team grants (non-owner) into `core.actor_app_role_grant`; validate ≥1 framework/domain/jurisdiction + all three attestations + TLA shape; attribution server-set (D6) — `hub/src/verity/hub/application/service.py`
- [X] T022 [US1] Router `POST/GET /applications`, `GET /applications/{id}` (gated `onboard_application` / `view`; FK→400, cardinality/attestation→400, duplicate TLA→409) — `hub/src/verity/hub/application/router.py`
- [X] T023 [US1] Wire `app.include_router(application_router)`; **supersede** the Slice-1 intake `POST /applications` (remove/redirect the instant create) — `hub/src/verity/hub/app.py`, `hub/src/verity/hub/intake/router.py`
- [X] T024 [US1] e2e test (PG18) — `hub/tests/verity/hub/application/test_onboarding.py`: propose → `pending` + perimeter + owner; viewer 403 / GET 200; bad cardinality + missing attestation → 400; duplicate TLA → 409

**Checkpoint**: US1 independently runnable + tested (the MVP).

---

## Phase 4: User Story 2 (P2) — Governed approval (the minimal primitive)

**Goal**: submit opens the onboarding approval; the required sign-offs resolve it and activate the app.
**Independent test**: submit opens an `application_onboarding` request with **computed** required roles (AI Governance + business-owner-if-not-proposer); the required `approve` sign-offs flip the app to `active` and write the `app_owner` grant; an incomplete set leaves it `pending`; a non-required approver is 403.

- [ ] T025 [P] [US2] Raw SQL approval primitive — `hub/db/queries/approval.sql` (`open_request`, `get_request`, `list_signoffs`, `insert_signoff`, `set_request_status`, `set_application_active`, `insert_app_owner_grant`)
- [ ] T026 [P] [US2] Models `ApprovalRequest` / `Signoff` / `SubmitForApproval` — `hub/src/verity/hub/approval/models.py`
- [ ] T027 [US2] Approval service — `open_request(kind, target, required_roles)`, `record_signoff`, resolve-when-satisfied (D-ONB-1) — `hub/src/verity/hub/approval/service.py`
- [ ] T028 [US2] Onboarding submit/resolve in `application/service.py` — compute required = `ai_governance` + business-owner-if-not-proposer; on resolve → status `active` + write the `app_owner` grant (FR-IN-015)
- [ ] T029 [US2] Routes `POST /applications/{id}/submit` + `GET /approvals/{id}` + `POST /approvals/{id}/signoff` (gated `onboard_application` / `view` / `signoff`) — `hub/src/verity/hub/approval/router.py`, `application/router.py`
- [ ] T030 [US2] Wire `approval_router`; 403 (non-required approver) / 409 (already resolved) handling — `hub/src/verity/hub/app.py`
- [ ] T031 [US2] e2e tests — `test_onboarding.py` (submit→signoff→`active` + `app_owner` grant; incomplete set → still `pending`; non-required approver 403) + `hub/tests/verity/hub/approval/test_approval.py` (primitive in isolation: open → signoff → resolve)

---

## Phase 5: User Story 3 (P3) — Enforcement & lifecycle

**Goal**: a non-`active` app can't own promotable intakes/assets; the classification ceiling is enforced; suspend/retire.
**Independent test**: a `pending` app rejects intake creation/promotion; an intake classification above the app ceiling is rejected (400); `suspend`/`retire` transitions persist.

- [ ] T032 [P] [US3] Raw SQL lifecycle + ceiling read — `application_onboarding.sql` (`set_application_status`, `get_application_ceiling`)
- [ ] T033 [US3] Service lifecycle (`suspend`/`retire`, guarded) + a `ceiling_ok(intake_classification)` helper — `hub/src/verity/hub/application/service.py`
- [ ] T034 [US3] Enforce the **active-app gate** + ceiling on the intake side (intake create requires `application_status = active`; intake classification ≤ app ceiling) — reconcile with Slice-1 `hub/src/verity/hub/intake/{service,router}.py`
- [ ] T035 [US3] Route `POST /applications/{id}/lifecycle` (gated `onboard_application`) — `hub/src/verity/hub/application/router.py`
- [ ] T036 [US3] e2e tests — `test_onboarding.py`: `pending` app blocks intake create; ceiling violation → 400; suspend/retire transitions

---

## Phase 6: Polish & cross-cutting

- [ ] T037 [P] Dev console read-only queries (applications by status, perimeter, pending onboarding approvals) — `tools/src/verity/dev/catalog.py`
- [ ] T038 [P] Refresh `quickstart.md` (resolve the `<actor-uuid>` note; confirm acceptance mapping)
- [ ] T039 Full hub suite green (`pytest -q`) + `ruff check` clean + `migrate`/`reset` idempotent on PG18

---

## Dependencies & order

- **Phase 2 blocks Phase 3+** (the schema must be grown + reviewed first).
- **US1 → US2 → US3**: US2 approves an app US1 proposes; US3 enforces gates over `active` apps. US1 is the MVP.
- **Cross-slice**: T023 supersedes the Slice-1 instant create; T034 adds the active-app gate to the shipped intake create — both touch Slice-1 code (update its tests).

## Parallel opportunities

- **Phase 2** is highly parallel: T004–T011 are independent files (the ALTERs + new tables/vocabs); T012–T014 (seeds) follow; T016 (migration) consolidates; T017 reviews.
- Within a story, `[P]` SQL/model tasks run together; service → router → test are sequential.
- Example (US1): T018, T019, T020 in parallel → T021 → T022 → T023 → T024.

## Implementation strategy

- **MVP = US1** (propose a `pending` application + perimeter): the smallest governed, tested increment.
- Then US2 (approval → `active`) and US3 (enforcement). Review the **Phase-2 migration before wiring services** (Principle II).

## Deferred (NOT in this slice — recorded)

The onboarding **UI build** (screen is a contract only); **environments / harness** management (FR-IN-016 tabs); FR-AP-* approval features beyond the onboarding need; **obligation resolution** (the perimeter is captured here; elicitation is the assessment slice).
