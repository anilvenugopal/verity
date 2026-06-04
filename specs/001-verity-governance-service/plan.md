# Implementation Plan: Intake vertical slice (verity-governance-service)

**Branch**: `001-verity-governance-service` | **Date**: 2026-06-04 | **Spec**: [spec.md](./spec.md)

**Input**: Feature specification from `specs/001-verity-governance-service/spec.md`

**Scope note**: This plan covers the **first vertical slice — Intake** — of the governance
service, per the constitution's PCR §6 sequencing (intake → registry → … ). Later slices
(registry/compose, harness/packaging/deploy, decision logging, lifecycle, compliance,
reporting) get their own plans.

## Summary

The intake slice is the front door of governance: **application onboarding → intake
(classified by EU-AI-Act risk tier + NAIC/internal materiality) → typed requirements**,
exposed through the **action-gated, fail-closed** governance API. Every status change is
written to the append-only `audit.status_transition` log, and every write is attributed to
`actor_id + acting_role` (D6). It is **hub-only** (no harness, NATS, or MinIO) and builds on
the committed, PG18-tested foundation (the `verity.hub` service: FastAPI · psycopg v3 async ·
raw SQL via aiosql · Pydantic v2 · the auth wiring). Data is the existing canonical schema —
no DDL changes.

## Technical Context

**Language/Version**: Python 3.12

**Primary Dependencies**: FastAPI; psycopg v3 (async) + psycopg_pool (dict_row); aiosql (raw
SQL, no ORM — ADR-0012); Pydantic v2. Test: pytest + testcontainers.

**Storage**: PostgreSQL 18 (pgvector). Canonical schema `specs/schema/verity_schema.sql` +
`seed/` — **no schema changes in this slice**. Tables used: `core.application`, `core.intake`,
`core.intake_requirement`, `audit.status_transition`; reference vocabs `reference.{intake_status,
ai_risk_tier, naic_materiality, materiality_tier, requirement_kind, requirement_status}`.

**Testing**: pytest against an ephemeral `pgvector/pgvector:pg18` testcontainer; tests mirror
the package (`tests/verity/hub/intake/`). The container is the safety net for raw SQL (ADR-0012).

**Target Platform**: Linux server (the `hub` component, package `verity.hub`). Local dev via
the `dev` console's `pg` container; prod is K8s/Helm + CloudNativePG.

**Project Type**: web service (the governance API) within the modular monorepo (ADR-0011).

**Performance Goals**: a cache-hit authorization decision adds no DB round-trip (NFR-005);
intake is low-volume Tier-1 CRUD — no special performance work.

**Constraints**: raw SQL / no ORM (constitution Technical Standards; ADR-0012); every status
change append-only-audited (D4); attribution `actor_id + acting_role` on every write (D6);
naming gate — API/model field names mirror schema columns exactly (NFR-007).

**Scale/Scope**: ~11 endpoints, 3 core tables + 1 audit table, 6 reference vocabularies.

## Constitution Check

*GATE: Must pass before Phase 0. Re-checked after Phase 1 (below).*

| Principle / Gate | Assessment |
|---|---|
| **I. Spec precedes implementation** | This plan + the 001 spec drive code; `/speckit.tasks` → `/speckit.implement` follow. **Deviation (recorded):** the foundation + auth were written ahead of this plan — see Complexity Tracking; kept as completed setup per product-owner decision, not re-derived. |
| **II. Schema is the hardened foundation** | Schema is reviewed, PG18 load-tested, and documented; intake depends only on existing tables — no DDL. **PASS.** |
| **III. Legacy is reference** | No imports from `verity_legacy`. (uw_demo is re-authored *demo data in app-alpha*, not this slice.) **PASS.** |
| **IV. API-only governance boundary** | Constrains the *harness*, not the hub. Intake is hub-internal; the hub *is* the governance API and owns its DB writes. **PASS (n/a to intake).** |
| **V. Uniform bindings, agent-only tools** | Intake introduces no bindings/tools/agents/MCP. **N/A.** |
| **VI. Slice-first, parity committed** | Intake is the first vertical per PCR §6. Deferred intake capabilities are recorded as **deferred-not-dropped** (below). **PASS.** |
| **VII. Governed deployment** | No packages/deploy in intake. **N/A.** |
| **VIII. Continuous compliance** | Intake is the *start* of the compliance lifecycle; this slice stops **before** obligation-resolution → the compliance metamodel (deferred). No compliance gate is bypassed. **PASS.** |
| **Naming gate** | Pydantic/API fields mirror schema column names exactly. **PASS.** |
| **Capability gate** | Deferrals recorded (research.md + below). **PASS.** |

**Deferred-not-dropped (capability gate):** intake status *state-machine* (this slice accepts
any valid `reference.intake_status`); requirement **embeddings + semantic dedup** (`vector(384)`);
**obligation-resolution → compliance** metamodel; **plan/estimate/ROI/cost**. Each is a later
intake slice, tracked here so parity stays honest.

## Project Structure

### Documentation (this feature)

```text
specs/001-verity-governance-service/
├── plan.md          # this file
├── research.md      # Phase 0 (decisions)
├── data-model.md    # Phase 1 (entities used + transitions)
├── quickstart.md    # Phase 1 (how to run/verify the slice)
├── contracts/
│   └── intake-openapi.yaml   # Phase 1 (the intake API contract)
└── tasks.md         # Phase 2 (/speckit.tasks — NOT created here)
```

### Source Code (repository root)

```text
hub/                                  # the governance hub component (ADR-0011)
└── src/verity/hub/
    ├── app.py                        # + app.include_router(intake_router)
    ├── auth/                         # existing (matrix, AuthContext, require_action)
    └── intake/                       # NEW (this slice)
        ├── __init__.py
        ├── models.py                 # Pydantic boundary models (mirror schema columns)
        ├── service.py                # multi-statement ops (create, status-transition+audit)
        └── router.py                 # APIRouter, action-gated routes
hub/db/queries/                       # NEW raw SQL (aiosql)
    ├── application.sql
    ├── intake.sql
    ├── intake_requirement.sql
    └── status_transition.sql
hub/tests/verity/hub/intake/          # NEW tests (mirror the package)
    └── test_intake.py
tools/src/verity/dev/catalog.py       # + read-only intake queries (dev console)
infra/README.md                       # + one line: hub-only features run on the pg substrate
```

**Structure Decision**: extends the existing `verity.hub` package with an `intake/` subpackage
(router/service/models), backed by per-aggregate `.sql` files; no new top-level structure.
Demo data is **not** here — it lives in `app-alpha/`, orchestrated by the `dev` console
(product-owner direction).

## Complexity Tracking

| Violation | Why it happened | Resolution (simpler alternative) |
|---|---|---|
| Foundation + auth implemented **before** this plan (Principle I) | Phase-2 scaffolding was built directly against the umbrella spec instead of through `/speckit.plan → tasks → implement`. | Per product-owner decision: **keep** the committed, PG18-tested foundation and back-fill it into `tasks.md` as completed setup, rather than re-deriving working code. From this slice on, all code flows through Spec Kit. |
| Raw SQL + thin repo (not an ORM) | Intentional (ADR-0012; constitution mandates raw SQL). | Not a violation — recorded for clarity; the testcontainer is the column-drift safety net. |

## Constitution Re-check (post-Phase 1)

After the Phase 1 design (data-model.md, contracts/, quickstart.md): no new violations. The
slice touches only existing reviewed tables, introduces no harness/DB-boundary change, no
bindings, and records every deferral. Gates I (with the recorded deviation), II, VI, naming,
and capability all hold. **Cleared to `/speckit.tasks`.**
