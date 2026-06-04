---
description: "Task list — Intake slice (001-verity-governance-service)"
---

# Tasks: Intake slice — verity-governance-service

**Input**: Design documents in `specs/001-verity-governance-service/` (plan.md, research.md,
data-model.md, contracts/intake-openapi.yaml, quickstart.md).

**Tests**: INCLUDED — the product owner requested PG18 end-to-end tests per story.

**Organization**: by user story for independent implementation/testing. The committed,
PG18-tested foundation is recorded as **done [X]** (Complexity Tracking in plan.md); it is not
re-derived.

## Format: `[ID] [P?] [Story] Description`
- **[P]**: parallelizable (different files, no incomplete-task dependency)
- **[Story]**: US1–US4 (user-story phases only)
- Paths are repo-relative; the hub component is `hub/` (package `verity.hub`).

---

## Phase 1: Setup — DONE (committed; recorded for traceability, not re-done)

- [X] T001 Hub component scaffold: `verity.hub` package — FastAPI app, config, psycopg v3 async pool, aiosql raw-SQL loader, thin repo — `hub/src/verity/hub/{app,config,db,repo}.py` (commits 6a1d168, 0a3772d)
- [X] T002 Migration/reset runner from the canonical DDL + seeds (ADR-0012) — `hub/src/verity/hub/migrate.py`
- [X] T003 PG18 testcontainer harness; tests mirror the package — `hub/tests/verity/hub/`
- [X] T004 Auth wiring: mock authenticator (e2e), Entra stub, fail-closed action matrix, `audit.auth_event` — `hub/src/verity/hub/auth/`

## Phase 2: Foundational — finalize the uncommitted foundation-prep (BLOCKS all stories)

- [ ] T005 Finalize `dict_row` on the pool and the two scalar auth queries (→ select-one named) — `hub/src/verity/hub/db.py`, `hub/db/queries/health.sql` (`count_roles`), `hub/db/queries/auth.sql` (`has_role_grant`), and call sites `hub/src/verity/hub/auth/authenticator.py`, `hub/src/verity/hub/app.py` (`readyz`)
- [ ] T006 [P] Add `AuthContext(principal, action, acting_role)` — `hub/src/verity/hub/auth/models.py`
- [ ] T007 [P] Add `acting_role_for()` + the `onboard_application` matrix cell — `hub/src/verity/hub/auth/matrix.py`
- [ ] T008 `require_action` returns `AuthContext`; update the `/admin/roles` handler — `hub/src/verity/hub/auth/dependencies.py`, `hub/src/verity/hub/app.py`
- [ ] T009 [P] Absolute `verity.*` imports across `hub/` + `tools/`; ruff `ban-relative-imports` rule — `hub/pyproject.toml`, `tools/pyproject.toml`
- [ ] T010 Create the intake package init so `app.py`'s `intake_router` import resolves — `hub/src/verity/hub/intake/__init__.py`; then run `pytest -q` to confirm the existing suite is green

**Checkpoint**: hub imports cleanly; all existing tests pass before any story work.

---

## Phase 3: User Story 1 (P1) — Onboard application & create intake  🎯 MVP

**Goal**: a governance user registers an application and opens an intake under it; reads work; every route is action-gated.
**Independent test**: an `onboard_application`-authorized principal creates an application and an intake and reads both; a `viewer`-only principal is denied (403) on create and allowed (200) on GET; writes record `created_by_actor_id + acting_role`.

- [ ] T011 [P] [US1] Raw SQL for applications (`create_application`, `list_applications`, `get_application`) — `hub/db/queries/application.sql`
- [ ] T012 [P] [US1] Raw SQL for intake create/read (`create_intake`, `get_intake`, `list_intakes_by_application`) — `hub/db/queries/intake.sql`
- [ ] T013 [P] [US1] Pydantic boundary models `ApplicationCreate/Application`, `IntakeCreate/Intake` — fields mirror schema columns (naming gate) — `hub/src/verity/hub/intake/models.py`
- [ ] T014 [US1] Intake service: create/get/list (insert via the repo helper; attribution `actor_id + acting_role` server-resolved, D6) — `hub/src/verity/hub/intake/service.py`
- [ ] T015 [US1] Router: `POST/GET /applications`, `POST/GET /applications/{id}/intakes`, `GET /intakes/{id}` — gated `onboard_application` / `create_intake` / `view`; 404 on missing id — `hub/src/verity/hub/intake/router.py`
- [ ] T016 [US1] Wire `app.include_router(intake_router)` — `hub/src/verity/hub/app.py`
- [ ] T017 [US1] e2e test (PG18): onboard→create→read; viewer 403 on create / 200 on GET; attribution recorded — `hub/tests/verity/hub/intake/test_intake.py`

**Checkpoint**: US1 independently runnable + tested (the MVP).

---

## Phase 4: User Story 2 (P2) — Classify intake (risk + materiality)

**Goal**: set EU-AI-Act risk tier + NAIC/internal materiality on an intake.
**Independent test**: a `reclassify_risk`-authorized principal sets the codes and they persist; an invalid code returns 400 (not 500).

- [ ] T018 [P] [US2] Raw SQL `classify_intake` (UPDATE the three `*_code` columns, RETURNING) — `hub/db/queries/intake.sql`
- [ ] T019 [P] [US2] `IntakeClassify` model — `hub/src/verity/hub/intake/models.py`
- [ ] T020 [US2] Service `classify` + route `POST /intakes/{id}/classification` (gate `reclassify_risk`); map FK violation → 400 with the bad field (D-INT-7) — `hub/src/verity/hub/intake/{service,router}.py`
- [ ] T021 [US2] e2e test: classify sets codes; `ai_risk_tier_code:"bogus"` → 400 — `hub/tests/verity/hub/intake/test_intake.py`

---

## Phase 5: User Story 3 (P3) — Governed status transitions (audited)

**Goal**: change an intake's status; one transaction updates the row **and** appends to `audit.status_transition`.
**Independent test**: a status change updates `intake_status_code` and writes exactly one `audit.status_transition` row with `from_code`/`to_code`/`actor_id`/`acting_role_code`; an invalid status code returns 400.

- [ ] T022 [P] [US3] Raw SQL `get_intake_status`, `update_intake_status` (`hub/db/queries/intake.sql`) + `insert_status_transition` (`hub/db/queries/status_transition.sql`)
- [ ] T023 [P] [US3] `IntakeStatusChange` model — `hub/src/verity/hub/intake/models.py`
- [ ] T024 [US3] Service `change_status` — **single transaction** (read from_code → update → insert audit, D-INT-1); route `POST /intakes/{id}/status` (gate `triage_intake`) — `hub/src/verity/hub/intake/{service,router}.py`
- [ ] T025 [US3] e2e test: status change updates the row + exactly one audit row (from/to/actor/acting_role); invalid code → 400 — `hub/tests/verity/hub/intake/test_intake.py`

---

## Phase 6: User Story 4 (P3) — Requirements capture

**Goal**: add and list typed requirements on an intake (`embedding` null — deferred D-INT-6).
**Independent test**: an `edit_requirement`-authorized principal adds a requirement (embedding null) and lists it back.

- [ ] T026 [P] [US4] Raw SQL `add_requirement`, `list_requirements` — `hub/db/queries/intake_requirement.sql`
- [ ] T027 [P] [US4] `RequirementCreate/Requirement` models — `hub/src/verity/hub/intake/models.py`
- [ ] T028 [US4] Service + routes `POST/GET /intakes/{id}/requirements` (gates `edit_requirement` / `view`) — `hub/src/verity/hub/intake/{service,router}.py`
- [ ] T029 [US4] e2e test: add requirement (embedding null) + list — `hub/tests/verity/hub/intake/test_intake.py`

---

## Phase 7: Polish & cross-cutting

- [ ] T030 [P] Read-only intake queries in the dev console catalog (`intakes`, `status_history`, `requirements`) — `tools/src/verity/dev/catalog.py`
- [ ] T031 [P] One-line `infra/README.md` note: hub-only features run on the `pg` substrate (dev stack `pg`; prod CloudNativePG)
- [ ] T032 Full hub suite green (`pytest -q`) + quickstart smoke + `ruff check` clean

---

## Dependencies & order

- **Phase 2 blocks Phase 3+** (foundation must be finalized first).
- **US1 (P1) is the MVP and a prerequisite** for US2/US3/US4 (each acts on an intake created in US1).
- **US2, US3, US4 are independent of one another** (different endpoints), but they share
  `intake/service.py`, `intake/router.py`, and `intake.sql` — coordinate edits or do them in
  sequence to avoid churn.

## Parallel opportunities

- Within a story, the `[P]` tasks (SQL files, models) run in parallel; service → router → test
  are sequential (same files / build on each other).
- Example (US1): T011, T012, T013 in parallel → then T014 → T015 → T016 → T017.

## Implementation strategy

- **MVP = US1** (onboard application + create/read intake): the smallest end-to-end, auth-gated,
  tested increment. Ship/verify it before US2–US4.
- Then layer US2 (classify) → US3 (audited status) → US4 (requirements), each independently
  testable, finishing with the polish phase.

## Deferred (NOT in this slice — recorded, not dropped)

Intake status **state-machine** (legal transitions); requirement **embeddings + semantic dedup**;
**obligation-resolution → compliance** metamodel; **plan/estimate/ROI/cost**. Each is a later
intake slice (capability gate; plan.md).
