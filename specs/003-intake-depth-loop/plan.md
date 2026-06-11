# Implementation Plan: Intake Depth Loop — Obligations, Asset Promotion & Change Proposals

**Branch**: `003-intake-depth-loop` · **Spec**: [spec.md](spec.md) · **Date**: 2026-06-10

## Summary

Close the intake's downstream governance loop over the **existing hardened schema** (Principle II): resolve an intake's regulatory obligation set from the canonical metamodel (P1), gate registry-asset promotion on an approved intake + satisfied/excepted obligations (P2), and re-govern post-approval change via change proposals (P3). The defining constraint — the user's directive and **Constitution Principle VIII** — is that **the metamodel is the single source of truth**: obligations, controls, evidence and tier ladders live only in the canonical metamodel, the assessment maps to canonical-requirement tier criteria (not bespoke logic), and *"has requirement R at tier N been met?"* is a tier-cumulative **metamodel query**. This feature is **seed + service + UI** — no metamodel schema design (verified present).

## Technical Context

**Language/Version**: Python 3.12 (backend), TypeScript 5 / React 18 (portal)
**Primary Dependencies**: FastAPI · psycopg v3 (async, dict_row) · raw SQL via aiosql (ADR-0012) · Pydantic v2 · Vite 5 · React Router v6
**Storage**: PostgreSQL 18 (pgvector); the compliance metamodel + obligation/exception/executable tables already exist in `specs/schema/` (verified). Hand-written numbered SQL migrations; governed seed in `specs/schema/seed/` (separate from `./dev demo`).
**Testing**: pytest + testcontainers (PG18) for the hub; portal `tsc --noEmit` + `vite build`; mock-auth (`VERITY_MOCK_PLATFORM_ROLES`) end-to-end with separation of duty.
**Target Platform**: Linux server (hub) behind the API-only governance boundary (Principle IV); K8s/Helm target (no Compose as source of truth).
**Project Type**: web — governance API (hub) + React portal.
**Performance Goals**: obligation resolution is a bounded metamodel query per intake (≤ low-hundreds of rows for the curated seed) — interactive (<300ms typical); no batch/throughput target.
**Constraints**: metamodel is the source of truth (no bespoke requirement lists, FR-019); resolution must be deterministic + reproducible (`derivation_method`/`ontology_version`), reasoner-ready but rule-resolved here; raw SQL only (no ORM); legacy is reference-only (Principle III).
**Scale/Scope**: P1 obligations (resolution + evidence + exceptions + Risk & Obligations UI); P2 minimal registry primitive + linking + promotion gate; P3 change proposals. Curated metamodel seed across 5 frameworks.

## Constitution Check

*GATE: must pass before Phase 0. Re-checked after Phase 1.*

| Principle | Bearing on 003 | Status |
|---|---|---|
| **I. Spec precedes implementation** | This plan traces to `spec.md` (approved, 0 open clarifications). | PASS |
| **II. Schema is the hardened foundation** | No metamodel schema design — the tables exist and were verified (2026-06-10). At most one small change-proposal grouping table (P3) — flagged for schema review before use. | PASS (P3 table → review) |
| **III. Legacy is reference** | Compliance/obligation concepts re-authored from Principle VIII + the frameworks; nothing imported from `../verity_legacy`. | PASS |
| **IV. API-only governance boundary** | All obligation/evidence/exception/link/promote/change actions are hub HTTP endpoints; the portal calls them; no DB credentials leak. | PASS |
| **VII. Governed deployment & lifecycle gates** | The promotion gate is a lifecycle gate (champion needs an approved intake + resolved obligations), aligned with the package/lifecycle stage→environment rules. | PASS |
| **VIII. Continuous, control-and-evidence-based compliance** | **003 directly implements VIII**: provisions→canonical requirements (cumulative tiers)→controls (4 phases)→evidence; obligations resolved from intake onward; exceptions first-class + append-only. Metamodel-as-source-of-truth and tier-cumulative queryability are VIII verbatim. | PASS (mandated) |
| **Technical Standards** (raw SQL ADR-0012, seed governance, `.venv`, UI-kit conformance) | Followed: aiosql + thin repos; governed seed separate from demo; portal reuses the shipped kit. | PASS |

No violations. No Complexity-Tracking justifications required (see below).

## Project Structure

### Documentation (this feature)
```
specs/003-intake-depth-loop/
├── spec.md            # the approved spec
├── plan.md            # this file
├── research.md        # Phase 0 — resolution query, mapping layer, seed, gate, registry, exception/change modeling
├── data-model.md      # Phase 1 — entities, states, the resolution query, new actions, API surface
├── contracts/
│   └── obligations-api.yaml   # new hub endpoints (obligations, evidence, exceptions, assets, links, promote, change)
├── quickstart.md      # Phase 1 — end-to-end demo
└── checklists/requirements.md
```

### Source Code (repository root)
```
hub/
├── db/
│   ├── migrations/            # numbered SQL: new action rows; the (optional) change-proposal grouping table
│   ├── queries/
│   │   ├── compliance.sql     # metamodel reads: resolve applicable requirements/tiers/controls/evidence
│   │   ├── obligation.sql     # intake_obligation(_resolution) read/write; evidence; rollup
│   │   ├── compliance_exception.sql
│   │   ├── registry.sql       # executable + executable_version + lifecycle/champion (minimal primitive)
│   │   └── intake_entity_link.sql
│   └── seed/                  # GOVERNED metamodel seed: provisions, canonical requirements, tiers, controls, evidence specs
├── src/verity/hub/
│   ├── compliance/            # metamodel read service + the obligation-RESOLUTION query (the heart of VIII)
│   ├── obligation/            # per-intake resolution + evidence + rollup (router/service/models)
│   ├── exception/             # compliance exceptions (raise → approve_exception sign-off → expiry)
│   ├── registry/              # minimal executable/version/lifecycle primitive + the PROMOTION GATE
│   ├── intake_link/           # intake↔asset linking + roll-up
│   ├── change_proposal/       # risk_reclassification / business_change re-approval + asset fork
│   ├── assessment/            # + a MAPPING LAYER: answers/scoring → canonical-requirement tier criteria (FR-021)
│   └── auth/matrix.py         # new actions: approve_exception, record_evidence, link_asset, promote_asset, propose_change
└── portal/src/pages/
    ├── intakes/               # Risk & Obligations surface (tab), evidence/exception affordances, asset roll-up + link/promote
    └── registry/              # thin asset list + create/advance/link/promote (minimal)
```

**Structure decision**: extends the existing modular monorepo (ADR-0011); each concern is its own hub module owning its SQL + thin repo (Technical Standards: "place responsibilities in the service that owns the concern"). The **metamodel resolution** lives in `compliance/` and is consumed by `obligation/`, the promotion gate (`registry/`), and the assessment mapping layer — one resolution path, no duplication (FR-019).

## Complexity Tracking

No constitution violations requiring justification. One watch item: the **change-proposal grouping** (P3) may need a small new table (per 001's design note "at most one small grouping table"); if so it goes through schema review (Principle II) before use — the only candidate schema growth, and additive.

## API Gap Analysis (new hub endpoints — detailed in contracts/)

| Capability | Endpoint(s) | Gate (action) |
|---|---|---|
| Resolve / read obligations | `GET /intakes/{id}/obligations` (+ resolve-on-assessment-save, internal) | `view` / `edit_impact_assessment` |
| Record evidence → satisfied | `POST /obligations/{id}/evidence` | `record_evidence` (new) |
| Raise / sign off exception | `POST /intakes/{id}/exceptions`, `POST /exceptions/{id}/signoff` | `edit_impact_assessment` / `approve_exception` (new) |
| Metamodel status (acid test) | `GET /requirements/{code}/status?intake={id}&tier=N` | `view` |
| Registry asset primitive | `POST /executables`, `POST /executables/{id}/versions`, `POST /versions/{id}/lifecycle` | `author_registry` / `promote_registry` |
| Promotion gate | enforced inside lifecycle advance (champion needs approved intake + resolved obligations) | `promote_registry` |
| Asset linking + roll-up | `POST /intakes/{id}/links`, `DELETE /links/{id}`, roll-up on `GET /intakes/{id}` | `link_asset` (new) |
| Change proposal | `POST /intakes/{id}/change-proposals` (+ shared `/approvals/{id}/signoff`), fork on approve | `reclassify_risk` (exists) |

The portal contract (`specs/002-.../contracts/portal-api.yaml`) is extended for the portal-called subset.

## Next

`/speckit-tasks` to generate the dependency-ordered task list (P1 → P2 → P3; the metamodel seed + resolution first, since the gate and the mapping layer both depend on it).
