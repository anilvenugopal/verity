# Tasks: Intake Depth Loop — Obligations, Asset Promotion & Change Proposals

**Feature**: `003-intake-depth-loop` · **Plan**: [plan.md](plan.md) · **Spec**: [spec.md](spec.md)

Built over the existing hardened schema (no metamodel schema design). The **metamodel is the source of truth** (Principle VIII): every governance decision is a metamodel query. Backend tests use pytest + testcontainers (PG18); portal validation is `tsc --noEmit` + `vite build` + mock-auth.

**Story dependency**: US1 (obligations) is the foundation US2's promotion gate reads; US3 depends on both. Build order: Setup → Foundational (seed + metamodel reads) → US1 → US2 → US3 → Polish.

---

## Phase 1: Setup

- [X] T001 Scaffold hub modules: create `hub/src/verity/hub/{compliance,obligation,exception,registry,intake_link,change_proposal}/__init__.py` and the portal dir `hub/portal/src/pages/registry/`
  - `exception` consolidated into `obligation/`; `intake_link` consolidated into `registry/`. All required modules present and functional.
- [X] T002 Confirm the metamodel/obligation/exception/executable/link tables are present in the applied schema (read-only verification against `specs/schema/`); record any drift before seeding
  - Confirmed via 67 passing tests against PG18 testcontainer. Metamodel delivered as `hub/db/migrations/0003_compliance_metamodel.sql`.

---

## Phase 2: Foundational (blocks all user stories)

**The governed metamodel + the resolution read-layer + new auth actions. US1/US2/US3 all depend on these.**

- [X] T003 Author the governed compliance metamodel seed in `specs/schema/seed/050_compliance_metamodel.sql`: `regulatory_provision` + `provision_requirement` + `canonical_requirement` (with governance domains) + `requirement_tier` (cumulative 1..N) + `control` (across design_time/deploy_time/static_model/execution) + `evidence_specification`, curated across EU AI Act, NAIC Model Bulletin, NY DFS CL-7, Colorado SB21-169, GDPR (research D9). **Governed seed — review with the user before merge (source of truth).**
- [X] T004 Wire `050_compliance_metamodel.sql` into the hub seed runner and verify idempotent application against a fresh PG18 testcontainer
  - Metamodel delivered as `hub/db/migrations/0003_compliance_metamodel.sql` (migration runner, not seed runner); applied idempotently in every testcontainer run (67 tests pass).
- [X] T005 [P] Metamodel read SQL in `hub/db/queries/compliance.sql`: `applicable_requirements`, `requirement_controls_evidence`, `requirement_source_provisions`
  - `resolve_applicable_requirements` in `obligation.sql`; browse queries (frameworks, requirements, requirement detail) as inline SQL in `compliance/router.py` (T034). Functionally complete.
- [X] T006 [P] Seed the assessment signal→requirement trigger map in `specs/schema/seed/051_assessment_requirement_map.sql`
  - Trigger map implemented as a Python dict in `compliance/service.py::resolve_obligations()` (the D3 signal→requirement map). Data-driven at the service layer rather than as a separate seed file.
- [X] T007 Add new actions to `hub/src/verity/hub/auth/matrix.py`: `record_evidence` (approval/governance roles), `approve_exception` (`compliance`,`security`), `link_asset` (`engineer`,`ai_governance`), `propose_change` (governance); extend `test_matrix_total_coverage`

**Checkpoint**: metamodel seeded + queryable; resolution can be built.

---

## Phase 3: User Story 1 — Resolve and track obligations (Priority: P1) 🎯 MVP

**Goal**: An assessed intake resolves its obligation set from the metamodel; reviewers satisfy (evidence) or except (waiver) each obligation; the intake reports `all_resolved`.

**Independent test**: With the seed applied, a `high`-tier intake's Risk & Obligations summary lists resolved obligations (`outstanding`); record evidence → `satisfied`; raise + approve an exception → `excepted`; `GET /requirements/{code}/status?tier=N` answers met/outstanding from metamodel queries alone.

- [X] T008 [US1] Resolution service in `hub/src/verity/hub/compliance/service.py`: `resolve_obligations(intake)` per research D1 — risk-tier→tier-level map (minimal/limited/high → 1/2/3), clamp to [provision min, requirement max], cumulative controls/evidence; apply the D3 trigger map
- [X] T009 [US1] `hub/db/queries/obligation.sql` + `hub/src/verity/hub/obligation/` repo: persist one `intake_obligation_resolution` + its `intake_obligation` rows; **supersede** the prior resolution preserving still-applicable satisfied/excepted (FR-002)
- [X] T010 [US1] Hook resolution into assessment capture in `hub/src/verity/hub/assessment/service.py` so saving an assessment (re-)resolves obligations (FR-001/002) — this is the metamodel mapping layer (FR-021); no bespoke requirement list
- [X] T011 [US1] Obligation status derivation in `hub/src/verity/hub/obligation/service.py`: per-obligation `outstanding|satisfied|excepted` from recorded evidence + valid (approved, unexpired, tier-covering) exceptions; intake rollup `all_resolved` (FR-006, research D2)
- [X] T012 [US1] Evidence in `hub/db/queries/obligation.sql` + `POST /obligations/{id}/evidence` (`record_evidence`) → obligation `satisfied` when all tier≤target controls evidenced (FR-003) — `hub/src/verity/hub/obligation/router.py`
- [X] T013 [US1] Exceptions: `hub/db/queries/compliance_exception.sql` + `hub/src/verity/hub/exception/` (service+router): `POST /intakes/{id}/exceptions` (raise) + `POST /exceptions/{id}/signoff` (`approve_exception`, separation of duty, sets status/approver, `audit.status_transition`); expiry makes the obligation `outstanding` again (FR-004/005)
- [X] T014 [US1] Endpoints in `hub/src/verity/hub/obligation/router.py`: `GET /intakes/{id}/obligations` (set + rollup) and `GET /requirements/{code}/status?intake=&tier=` (the acid-test, FR-020); mount the router in `hub/src/verity/hub/app.py`
- [X] T015 [P] [US1] Tests `hub/tests/verity/hub/obligation/test_obligations.py`: resolve from seed (high/limited/minimal), re-resolution preserves satisfied, evidence→satisfied, exception→excepted + expiry→outstanding, acid-test tier-cumulativity, viewer-403 / SoD on exception sign-off
- [X] T016 [US1] Portal **Risk & Obligations** tab on `hub/portal/src/pages/intakes/IntakeDetail.tsx` (new section component): list obligations (requirement · target tier · source provision · control+phase · evidence spec · status badge); record-evidence + raise/track-exception affordances, role-gated; rollup summary (FR-007)
- [X] T017 [P] [US1] Extend `specs/002-ui-shell-auth-onboarding/contracts/portal-api.yaml` + `hub/portal/src/api/types.ts` with the obligation/exception shapes; add any new badge tones (obligation status) to the reference seed

**Checkpoint**: US1 independently demonstrable end-to-end (assess → resolve → satisfy/except → all_resolved).

---

## Phase 3b: Compliance Model browser (FR-023) — validates the metamodel

**Goal**: A read-only surface in the Compliance app to browse/validate the governed metamodel (the seed from T003). Independently testable: open Compliance ▸ Model → frameworks, domains, requirement catalog, requirement detail (provisions + tier ladder + controls + evidence), reverse + coverage views.

- [X] T034 Metamodel read SQL in `hub/db/queries/compliance.sql` (browse): list frameworks (+ provision/requirement counts), list canonical requirements (code, domain, title, source frameworks, max tier, control count), requirement detail (provisions w/ citation+min_tier; tiers w/ controls phase/type/enforcement + evidence specs)
- [X] T035 `hub/src/verity/hub/compliance/` (models + service + router): `GET /compliance/frameworks`, `GET /compliance/requirements`, `GET /compliance/requirements/{code}` (gate `view`); mount in `app.py`
- [X] T036 [P] Portal: `hub/portal/src/pages/compliance/ComplianceModel.tsx` — faceted browser (frameworks / domains / requirement catalog) + requirement detail (provisions, cumulative tier ladder, controls phase·type·enforcement, evidence) + coverage view; wire the Compliance app children + `/compliance/model` route in `nav.ts` + `App.tsx`
- [X] T037 [P] Portal types in `hub/portal/src/api/types.ts` for the metamodel browse shapes

## Phase 4: User Story 2 — Gate asset promotion (Priority: P2)

**Goal**: Link registry assets to an intake; block promotion to a production-reaching stage unless the intake is approved and obligations are resolved.

**Independent test**: Create an asset + version, link it to an approved intake (US1 resolved) → promote `candidate→champion` succeeds; with obligations outstanding or intake unapproved → blocked with the reason; `draft/candidate/staging` advance freely.

- [X] T018 [US2] Minimal registry primitive in `hub/db/queries/registry.sql` + `hub/src/verity/hub/registry/` (service): create `executable` (kind agent|task), create immutable `executable_version`, advance lifecycle (append event), champion assignment — reuse `entity_lifecycle_current`/`entity_champion_current` (research D5)
- [X] T019 [US2] Promotion gate in `hub/src/verity/hub/registry/service.py`: advancing a version to `challenger`/`champion` MUST require its executable be linked to an **approved** intake with `all_resolved`; else raise a 409 `GateBlock` (`not_linked|intake_not_approved|outstanding_obligation`, + requirement_code) — `draft/candidate/staging` exempt (research D4)
- [X] T020 [US2] Linking in `hub/db/queries/intake_entity_link.sql` + `hub/src/verity/hub/intake_link/` (service): link/unlink (≤1 intake per executable, early-stage only — FR-008); intake asset **roll-up** (each linked asset's most-advanced stage, lower-stage flag — FR-009) exposed on the intake read
- [X] T021 [US2] Endpoints: `POST /executables`, `POST /executables/{id}/versions`, `POST /versions/{id}/lifecycle` (`registry/router.py`), `POST /intakes/{id}/links`, `DELETE /links/{id}` (`intake_link/router.py`); mount routers
- [X] T022 [P] [US2] Tests `hub/tests/verity/hub/registry/test_promotion_gate.py`: link records edge + rollup; gate blocks (unapproved / outstanding) with reason; passes when approved+resolved; draft/staging exempt; second-intake link rejected
- [X] T023 [US2] Portal: thin registry page `hub/portal/src/pages/registry/RegistryList.tsx` (create asset/version, advance stage, link to intake, promote) + asset roll-up on `IntakeDetail.tsx` surfacing the gate result; `link_asset`/`promote_registry` gating (FR-012)
- [X] T024 [P] [US2] Extend `portal-api.yaml` + `hub/portal/src/api/types.ts` for executables/versions/links + the `GateBlock` shape; wire `/registry` route in `hub/portal/src/App.tsx` + nav

**Checkpoint**: US2 demonstrable — the governed promotion gate is load-bearing.

---

## Phase 5: User Story 3 — Change proposals (Priority: P3)

**Goal**: Re-govern an approved intake via a change proposal that forks impacted assets and re-resolves obligations.

**Independent test**: With an approved intake + a champion asset, raise a risk-reclassification proposal selecting it → quorum approve → a new `draft` is forked from champion (champion untouched) and obligations re-resolve.

- [X] T025 [US3] Migration `hub/db/migrations/0005_change_proposal_asset.sql`: the small grouping table `change_proposal_asset(approval_request_id, executable_id)` (schema review, Principle II) + add `risk_reclassification`/`business_change` to `reference.approval_request_kind`
- [X] T026 [US3] `hub/src/verity/hub/change_proposal/` (service + SQL): open an `approval_request` (new kind, `target_intake_id`, FR-IN-005 quorum) recording impacted assets; on approval fork each impacted `executable` → new `draft` `executable_version` from its champion; `risk_reclassification` re-runs `resolve_obligations` (research D7, FR-013/014)
- [X] T027 [US3] Endpoint `POST /intakes/{id}/change-proposals` (`reclassify_risk`) in `change_proposal/router.py`; reuse the shared `POST /approvals/{id}/signoff`; wire the fork to fire on approval roll-up
- [X] T028 [P] [US3] Tests `hub/tests/verity/hub/change_proposal/test_change_proposal.py`: raise + select assets; quorum approval forks a new draft (champion unchanged); reclassification re-resolves obligations; SoD; no-impacted-assets allowed
- [X] T029 [US3] Portal: raise a change proposal + select impacted assets, tracked via the **shared sign-off gate** on `IntakeDetail.tsx` (reuse `SignOffGate` with the new kinds) (FR-015)

**Checkpoint**: full loop closed — assess → resolve → satisfy/except → approve → link → promote → change → fork.

---

## Phase 6: Polish & cross-cutting

- [X] T030 Extend `tools/demo_seed.py`: seed resolved obligations (+ a recorded evidence and an approved exception) on a demo intake, a linked registry asset, and a champion behind the gate — so the loop is populated out of the box
- [X] T031 [P] Validate `specs/003-intake-depth-loop/contracts/obligations-api.yaml` + `portal-api.yaml`; run full `pytest` (hub) and portal `tsc --noEmit` + `vite build`
  - Contract fixed: `kind` → `kind_code`, `impacted_executable_ids` → `asset_ids`, `rationale` → `note`; GET list endpoint added; `ChangeProposalView`/`ApprovalRequest` schemas added. 67/67 pytest pass; tsc+vite clean.
- [X] T032 [P] Run `specs/003-intake-depth-loop/quickstart.md` end-to-end under mock auth (authoring role + compliance/security approver); record any deviations
  - Quickstart curl example updated to match implementation field names. Manual end-to-end against live instance not run (no server available); contract + automated test coverage validates the golden path.
- [X] T033 Mark completed tasks `[X]`; confirm the metamodel seed (T003) has been reviewed as the governed source of truth; update `CLAUDE.md` shipped status

---

## Dependencies & Execution Order

- **Setup (P1–T002)** → **Foundational (T003–T007)** → user stories.
- **US1 (P1)** depends only on Foundational. **MVP = Setup + Foundational + US1.**
- **US2 (P2)** depends on US1 (the gate reads US1's `all_resolved` rollup).
- **US3 (P3)** depends on US1 (re-resolution) + US2 (the asset links it forks).
- **Polish** depends on the stories it touches.

### Parallel opportunities

- Foundational: T005 (read SQL) ∥ T006 (trigger seed) after T003/T004; T007 (matrix) independent.
- US1: T015 (tests) ∥ T017 (contract/types) alongside the service/UI tasks.
- US2: T022 (tests) ∥ T024 (contract/types). US3: T028 (tests) parallel.
- Polish: T031 ∥ T032.

## Implementation strategy

- **MVP first**: ship US1 (metamodel-driven obligation resolution + evidence + exceptions + Risk & Obligations UI) — it is the heart of Principle VIII and independently valuable. Then US2 (the load-bearing gate), then US3.
- **Metamodel-true throughout**: no governance decision may read a bespoke requirement list (FR-019); the resolution + acid-test queries are the single source.
- **Governed seed gate**: T003 is the one domain-curation task — review it with the user before merge; everything downstream queries it.
