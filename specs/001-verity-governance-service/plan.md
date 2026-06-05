# Implementation Plan — Application Onboarding slice

**Branch**: `001-verity-governance-service` · **Spec**: [spec.md](spec.md) (FR-IN-015…018, FR-AUTHZ-001, FR-AP-*)
**Slice**: Application onboarding — the governed proposal that creates the tenant-of-record and its compliance perimeter.

> **Slice history (one feature, sequential slices):**
> - **Slice 1 — Intake CRUD (shipped):** application/intake/classify/status/requirements US1–US4 (commits `8780d24`, `fc2dd8d`). Its plan artifacts are preserved in git history (`88f73f5`).
> - **Slice 2 — Application Onboarding (this plan):** supersedes the thin instant `POST /applications` from Slice 1 with a governed propose→approve flow.

## Summary

Application onboarding turns the thin Slice-1 `application` record into a **governed tenant-of-record**: a proposal (not an instant create) that captures **identity** (name, immutable 3-char TLA, purpose), **ownership** (business owner + initial app-team), and the **compliance perimeter** (data-classification ceiling, ≥1 regulatory framework / governance domain / jurisdiction, three explicit attestations), then requires an **AI-Governance + business-owner** approval before the application goes `active`. It also lands the **minimal, reusable approval primitive** (`approval_request` + `approval_signoff` over existing tables) that intake/change-proposals/exceptions will reuse.

## Technical Context

- **Stack:** Python 3.12 · FastAPI · psycopg v3 async · raw SQL via aiosql + thin repo (ADR-0012) · Pydantic v2 · PostgreSQL 18. (Unchanged from Slice 1.)
- **Package:** `verity.hub`; new module `verity.hub.application` (onboarding) + `verity.hub.approval` (the primitive). Tests mirror the package.
- **Data layer:** the canonical schema, **grown** for onboarding (DDL changes are spec-covered: FR-IN-015…018). Migrations are hand-written, numbered SQL (ADR-0012).
- **Existing infrastructure reused (no new tables for these):** `core.approval_request`, `core.approval_signoff`, `reference.approval_decision`, `reference.approval_request_status`, `core.actor_app_role_grant` (+ `current_actor_app_role` view), `reference.governance_domain` (the 9), `reference.data_classification` (sensitivity), `core.regulatory_framework`, the compliance metamodel (`canonical_requirement`/`control`/`evidence_specification`/`domain_maturity`).
- **NEEDS CLARIFICATION:** none blocking — resolved in research.md (D-ONB-1…7).

## Constitution Check

| Principle | Gate | Status |
|---|---|---|
| I — Spec precedes implementation | Onboarding is fully specced (FR-IN-015…018) before code | ✅ PASS |
| II — Schema is the hardened foundation | DDL growth is spec-covered + reviewed before service work; new objects follow naming-conventions.md | ✅ PASS (review the migration first) |
| III — Legacy is reference, never source | Re-author; `app_demo_*`→`app_*` rename recorded as an intentional v2 delta (not silent) | ✅ PASS |
| IV — API-only governance boundary | All writes via the governance API; attribution server-resolved (D6); no direct DB from callers | ✅ PASS |
| V — Uniform bindings, agent-only tools | N/A (no binding/tool surface in this slice) | ✅ N/A |
| VI — Slice-first, parity committed | Onboarding scoped; deferrals recorded (UI build, harness provisioning) — never silent | ✅ PASS |
| VIII — Continuous control-and-evidence compliance | Perimeter feeds obligation elicitation (FR-IN-014/018) — captured here, resolved downstream | ✅ PASS |

No violations. **Process note:** this slice grows the hardened schema — the migration DDL MUST be reviewed (Principle II) before the service layer is wired.

## Scope

**In scope**
- Schema growth (data-model.md): `core.application` columns (`code` TLA, `application_status_code`, `data_classification_code`, `line_of_business_code`, `affects_consumers`, `processes_pii`, `consumer_facing`); `core.approval_request.target_application_id`; new joins `application_regulatory_framework` / `_governance_domain` / `_jurisdiction`; new vocabs `reference.application_status` / `jurisdiction` / `line_of_business`; `app_team_role` rename `app_demo_*`→`app_*`; the `application_onboarding` approval kind.
- Reference seeds: `application_status`, `jurisdiction` (US states + EU/UK + …), `line_of_business`, a starter `regulatory_framework` set; verify/repair `data_classification` to the 4 sensitivity codes.
- The **minimal approval primitive** (`verity.hub.approval`): open request (kind, target, computed required-roles), record sign-off, resolve when satisfied.
- Onboarding API (contracts/onboarding-openapi.yaml): propose (`pending`), submit-for-approval, sign-off → `active` + owner grant, reads; **rework** the Slice-1 instant `POST /applications`.
- Enforcement: non-`active` application can't own promotable intakes/assets; classification-ceiling rule available to intakes.

**Out of scope (deferred — recorded):** the onboarding UI build (screen is a contract only); harness provisioning + environments (FR-IN-016 management tabs); FR-AP-* approval features beyond the onboarding need; obligation *resolution* (perimeter is captured here; elicitation is the assessment slice).

## User-story decomposition (drives /speckit.tasks)

- **Foundational** — schema migration (DDL growth + seeds + `app_*` rename), reviewed first; reconcile the Slice-1 `application` model.
- **US1 (P1) — Propose an application (MVP):** create a `pending` application capturing identity + ownership + compliance perimeter; reads. *Independent test:* an authorized author proposes an app; it persists `pending` with TLA unique/immutable + perimeter rows + owner recorded; a viewer is denied.
- **US2 (P2) — Governed approval:** submit-for-approval (open `application_onboarding` request; required roles = AI Governance + business-owner-if-not-proposer), sign-off, resolve → `active` + write the `app_owner` grant. *Independent test:* the required sign-offs flip the app to `active` and grant the owner; an incomplete set leaves it `pending`.
- **US3 (P3) — Enforcement & lifecycle:** non-`active` app can't own promotable intakes/assets; classification-ceiling check; `suspend`/`retire`. *Independent test:* a `pending` app rejects intake/asset promotion; a ceiling violation is rejected.

## Project structure (additions)

```
hub/
  db/queries/
    application_onboarding.sql      # propose/read/lifecycle
    application_perimeter.sql       # perimeter joins (frameworks/domains/jurisdictions)
    approval.sql                    # open request, signoff, resolve (the primitive)
  src/verity/hub/
    application/{models,service,router}.py   # onboarding (supersedes intake.Application bits)
    approval/{models,service}.py             # minimal approval primitive
  tests/verity/hub/
    application/test_onboarding.py           # PG18 e2e: propose→submit→signoff→active
    approval/test_approval.py                # the primitive in isolation
  migrations/000X_application_onboarding.sql # hand-written, numbered (ADR-0012)
specs/schema/                                # DDL growth (structure) + seeds — reviewed first
  core/{application,approval_request}.sql               # ALTER (new columns)
  core/{application_regulatory_framework,application_governance_domain,application_jurisdiction}.sql  # NEW
  reference/{application_status,jurisdiction,line_of_business}.sql                                    # NEW
  seed/...                                              # vocab seeds + app_team_role rename
```

## Complexity Tracking

| Item | Note |
|---|---|
| Schema growth on hardened tables | Spec-covered (FR-IN-015…018); migration reviewed before service (Principle II). |
| `app_demo_*`→`app_*` vocab rename | Touches SC-004 (verbatim-from-v1); recorded as an intentional v2 product rename (research D-ONB-6). |
| Minimal approval primitive | Built general (reused by intake/change-proposals/exceptions) but feature-scoped to the onboarding need. |
| Supersedes Slice-1 instant create | The thin `POST /applications` is reworked into propose→approve; Slice-1 tests update accordingly. |

## Phases

- **Phase 0 — research.md:** D-ONB-1…7.
- **Phase 1 — data-model.md + contracts/onboarding-openapi.yaml + quickstart.md:** the schema growth, the onboarding/approval API, and the propose→approve→active happy path.
- **Phase 2 — /speckit.tasks:** task breakdown by the user stories above.
