# Implementation Plan — Intake Approval slice

**Branch**: `001-verity-governance-service` · **Spec**: [spec.md](spec.md) (FR-IN-001/005, FR-AS-010, FR-AUTHZ)
**Slice**: the governed **intake approval** — open a `kind=intake` approval with the tier-based quorum (FR-IN-005); the quorum's sign-offs approve the intake.

> **Slice history (one feature, sequential slices):**
> - **Slice 1 — Intake CRUD** (`8780d24`, `fc2dd8d`).
> - **Slice 2 — Application Onboarding** (`4252d88`, `f222d71`, `7d0003e`, `8229063`) — built the reusable approval primitive.
> - **Slice 3 — Intake Assessment** (`596e94e` + prior) — computes the inherent risk tier.
> - **Slice 4 — Intake Approval (this plan):** reuses the Slice-2 approval primitive for intakes; the tier the Slice-3 assessment computed drives the FR-IN-005 quorum. Prior plans are in git history.

## Summary

An assessed intake (with a computed `ai_risk_tier_code`) is **submitted for approval**, opening a
`kind=intake` `approval_request` whose **required roles are the tier-based quorum** (FR-IN-005:
`high` → 5 roles, `limited` → 3, `minimal` → `business_owner`). When **every required role signs
off `approved`**, the intake is moved to `approved` (audited); any rejection blocks. This reuses
the Slice-2 primitive (`approval_request`/`approval_signoff` + the generic open/sign-off/resolve)
and the Slice-1 audited `change_status`. It also unblocks the deferred **FR-AS-010** "intake not
approvable while justifications outstanding" hook (the assessment must exist before submit).

## Technical Context

- **Stack:** unchanged. New module `verity.hub.intake_approval`. Tests mirror the package.
- **Data layer:** **no new tables** — `core.approval_request` already has `target_intake_id` and the
  `intake` kind is seeded; `core.approval_signoff` has the per-role uniqueness. The only schema-ish
  change is **generalizing `open_request`** (it currently hardcodes `target_application_id`) to also
  bind `target_intake_id` (the one-target CHECK still enforces exactly one).
- **Cross-slice reuse:** the Slice-2 approval primitive (`approval.service` open/sign-off/resolve),
  the Slice-1 audited `intake.service.change_status` (resolve → `approved`), the Slice-3 computed
  `ai_risk_tier_code`.
- **Architecture:** the **approval router's `/approvals/{id}` + `/signoff` become kind-dispatchers**
  (`application_onboarding` → onboarding resolution; `intake` → intake-approval resolution), so the
  generic surface serves both. NEEDS CLARIFICATION: none — D-IAP-1…5 in research.md.

## Constitution Check

| Principle | Gate | Status |
|---|---|---|
| I — Spec precedes implementation | FR-IN-001/005 specced | ✅ PASS |
| II — Schema is the hardened foundation | No new tables; one query generalization (reviewed) | ✅ PASS |
| IV — API-only governance boundary | Gated `edit_intake` (submit) / `signoff`; attribution server-resolved (D6) | ✅ PASS |
| VI — Slice-first, parity committed | Reclassification/change-proposal re-approval (FR-IN-013) deferred-with-reason | ✅ PASS |

No violations.

## Scope

**In scope**
- Generalize `approval.service.open_request` (+ the SQL) for `target_intake_id`.
- Kind-dispatch in the approval router (`get_request_view` + `sign_off`) → onboarding vs intake.
- **Submit** `POST /intakes/{id}/submit` (gated `edit_intake`): opens a `kind=intake` approval with
  the tier-based required roles; requires a computed tier (else 400); blocks a terminal/duplicate.
- **Sign-off resolution**: the per-tier quorum (FR-IN-005); a signer fills a required-role slot they
  hold (403 otherwise); when all required roles have `approved` → intake `approved` (audited
  `change_status`); any `rejected` → request rejected.

**Out of scope (deferred — recorded)**
- **Re-approval on reclassification / business change** (FR-IN-013 — the `risk_reclassification` /
  `business_change` kinds + impacted-asset selection + draft-fork) — a change-management slice.
- **Asset linking / promotion gate** (FR-IN-009) — the "approved intake unlocks promotion" half is a
  later slice (this slice produces the approved intake it will gate on).
- **Assessment-completeness gate** beyond "an assessment exists" (FR-AS-010 justifications) — lands
  with mitigations/obligations.

## User-story decomposition (drives /speckit.tasks)

- **Foundational** — generalize `open_request` (target_intake_id); make the approval router kind-dispatch.
- **US1 (P1) — Submit an intake for approval:** opens the `kind=intake` approval with the tier-based
  required roles; requires a computed tier. *Independent test:* a `high` intake → approval opened with
  the 5 required roles; `minimal` → `[business_owner]`; an unassessed intake (no tier) → 400.
- **US2 (P2) — Quorum sign-off → approve:** the required roles sign; the full quorum → intake
  `approved` (audited); a rejection → request rejected; a non-required-role signer → 403. *Independent
  test:* a `minimal` intake → `business_owner` signs → intake `approved` + one `audit.status_transition`
  row; a `high` intake with a partial quorum → still pending; a non-required signer → 403.
- **US3 (P3) — Guards:** one open approval per intake (re-submit → 409); a terminal intake can't be
  submitted (409). *Independent test:* double-submit → 409; submit a `rejected` intake → 409.

## Project structure (additions)

```
hub/
  db/queries/approval.sql                 # generalize open_request (+ target_intake_id); set_intake_approved reuse
  db/queries/intake_approval.sql          # get intake tier/status for the quorum + submit guard
  src/verity/hub/intake_approval/{models,service,router}.py   # submit + tier quorum + resolve
  src/verity/hub/approval/router.py       # kind-dispatch get_request_view + sign_off
  tests/verity/hub/intake_approval/test_intake_approval.py    # PG18 e2e
```

## Complexity Tracking

| Item | Note |
|---|---|
| Approval router becomes a kind-dispatcher | 2 kinds (onboarding, intake) via if/elif; keeps one generic `/approvals` surface. |
| `open_request` generalization | Bind both `target_intake_id`/`target_application_id` (one null); the one-target CHECK is the backstop. |
| Tier quorum is a fixed per-tier set | FR-IN-005 verbatim; richer than onboarding's computed pair but same resolve pattern. |
| Reuse, not rebuild | No new tables; submit/resolve reuse the Slice-2 primitive + Slice-1 audited change_status. |

## Phases

- **Phase 0 — research.md:** D-IAP-1…5.
- **Phase 1 — data-model.md + contracts/intake-approval-openapi.yaml + quickstart.md.**
- **Phase 2 — /speckit.tasks.**
