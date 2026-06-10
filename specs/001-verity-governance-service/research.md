# Phase 0 — Research & Decisions: Intake Approval slice

Decisions specific to intake approval. Reuses the Slice-2 approval primitive and the Slice-3 tier.

## D-IAP-1 — Reuse the approval primitive; generalize `open_request` for intakes
- **Decision**: intake approval is a `kind=intake` row in the existing `core.approval_request`
  (which already has `target_intake_id` and the seeded `intake` kind) with sign-offs in
  `core.approval_signoff`. The only change is generalizing `approval.service.open_request` (+ SQL)
  to bind **`target_intake_id`** as well as `target_application_id` (one is null; the
  `ck_approval_request_one_target` CHECK enforces exactly one).
- **Rationale**: the primitive was built general (Slice 2, D-ONB-1) precisely for this; no new tables.
- **Alternatives**: an intake-specific approval table (rejected — duplicates the primitive).

## D-IAP-2 — Tier-based quorum (FR-IN-005), computed (not stored)
- **Decision**: the required roles are computed from the intake's `ai_risk_tier_code`:
  `high → [business_owner, compliance, legal, model_risk, ai_governance]`;
  `limited → [business_owner, compliance, ai_governance]`; `minimal → [business_owner]`;
  `unacceptable → []`. Resolution = approved when **every** required role has an `approved` sign-off;
  any `rejected` blocks. (Same compute-don't-store pattern as onboarding, D-ONB-1.)
- **Rationale**: FR-IN-005 is policy beside the matrix; the request carries no `required_roles` column.
- **Alternatives**: store the quorum on the request (rejected — drifts from the tier).

## D-IAP-3 — Submit requires a computed tier; the assessment is the precondition
- **Decision**: `POST /intakes/{id}/submit` (gated `edit_intake`) opens the approval only if the
  intake has an `ai_risk_tier_code` (set by the Slice-3 assessment) — else 400 "intake not yet
  classified". This realizes the FR-AS-010 precondition ("assessment before approval") at the
  granularity available now (a tier exists). `unacceptable` intakes are already auto-rejected
  (Slice 3), so they cannot be submitted.
- **Rationale**: a quorum can't be computed without a tier; the assessment must precede approval.
- **Alternatives**: allow submit then block resolution (rejected — fails fast is clearer).

## D-IAP-4 — Sign-off fills a required-role slot the signer holds
- **Decision**: a sign-off is gated `signoff` (an approval-capable role); the finer check is that the
  signer **holds at least one required role for this intake's tier** (else 403), and the sign-off is
  recorded `signed_as` that role (one slot per role — `uq_approval_signoff_request_role`). Resolution
  counts distinct approved required-role slots.
- **Rationale**: mirrors the onboarding finer-gate (D-ONB self-approval/required-approver checks),
  generalized to a role set.
- **Alternatives**: let any approval role sign (rejected — FR-IN-005 names specific roles per tier).

## D-IAP-5 — Resolve via the audited `change_status`; one open approval per intake
- **Decision**: on a satisfied quorum the intake moves to `approved` via the Slice-1
  `intake.service.change_status` (one txn + `audit.status_transition`). An intake may have **one open
  `kind=intake` approval** at a time (a second submit → 409); a terminal intake (`rejected`/`retired`)
  cannot be submitted (409).
- **Rationale**: reuse the audited transition; avoid duplicate concurrent approvals.
- **Alternatives**: allow multiple open approvals (rejected — ambiguous quorum state).

## Error model (slice)
- `401/403` → `AuthError` (incl. "not a required approver for this tier").
- `404` → unknown intake / approval. `409` → no tier yet is 400 (below); duplicate open approval;
  terminal intake; already-resolved request. `400` → intake not yet classified (no tier);
  invalid `decision_code` (FK). `422` → request validation.
