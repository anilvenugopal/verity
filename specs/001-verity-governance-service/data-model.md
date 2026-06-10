# Phase 1 — Data Model: Intake Approval slice

**No new tables, no new columns.** This slice reuses the Slice-2 approval entities and the Slice-1
intake/audit entities. The only data-layer change is **generalizing the `open_request` query** to
bind `target_intake_id`.

## Reused as-is

### `core.approval_request`
| Column | Role this slice |
|---|---|
| `request_kind_code` | `'intake'` (already seeded) |
| `target_intake_id` | the intake under approval (FK exists; the one-target CHECK already allows intake XOR version XOR application) |
| `status_code` | `pending` → `approved`/`rejected` |
| `opened_by_actor_id` / `opened_role_code` | the submitter (server-resolved) |

### `core.approval_signoff`
`approval_request_id`, `approver_actor_id`, `signed_as_role_code` (a required role for the tier),
`decision_code` (→ `reference.approval_decision`), `comment`, `created_at` (now surfaced in the read
view — drives the onboarding workspace history timeline). `uq_approval_signoff_request_role` gives one
sign-off per role slot.

### `core.intake`
`ai_risk_tier_code` (read — drives the quorum; set by the Slice-3 assessment); `intake_status_code`
(written → `approved` on a satisfied quorum, via the Slice-1 audited `change_status`).

### `audit.status_transition`
One row per intake status change (the approval → `approved` transition), via `change_status`.

## The tier → quorum (FR-IN-005; computed, D-IAP-2)

| `ai_risk_tier_code` | required roles |
|---|---|
| `high` | `business_owner, compliance, legal, model_risk, ai_governance` |
| `limited` | `business_owner, compliance, ai_governance` |
| `minimal` | `business_owner` |
| `unacceptable` | `[]` (auto-rejected — cannot be submitted) |

## Relationships

```
intake (ai_risk_tier_code) ──submit──> approval_request (kind=intake, target_intake_id, status=pending)
                                              │ 1───* approval_signoff (signed_as_role, decision)
                                              └── all required roles approved ──> intake.status = approved
                                                                                  + audit.status_transition
```

## Validation rules (FR-IN-001/005, D-IAP-3…5)

- Submit requires `intake.ai_risk_tier_code` to be set (else 400); a terminal intake (`rejected`/`retired`) → 409; one open `kind=intake` approval per intake (duplicate → 409).
- A sign-off is gated `signoff` AND the signer must hold a required role for the tier (else 403); recorded `signed_as` that role; one slot per role.
- Resolution: approved only when every required role has an `approved` sign-off; any `rejected` → request rejected.
- The intake → `approved` transition is one audited transaction (`change_status`, D-INT-1).
- All writes record `created_by/role` server-side (D6).

## The only query change

`approval.sql` `open_request` is generalized to bind **`target_intake_id`** alongside
`target_application_id` (one null). The onboarding caller passes `target_intake_id = NULL`; the
intake caller passes `target_application_id = NULL`.

## Onboarding remediation reuse (FR-IN-015a — query-only, no schema change)

Pre-activation edit + rejection remediation reuse the existing tables; **no new tables or columns**:
- `update_application` edits a `core.application` row while `application_status_code = 'pending'`
  (guarded in SQL); its perimeter join rows are cleared + re-inserted in one transaction.
- `cancel_pending_application_approvals` sets any still-`pending` `core.approval_request` for the
  app to **`cancelled`** (a seeded `reference.approval_request_status` code) on re-submit, so one
  review is live. A `requested_changes` sign-off closes the request as `rejected` (no deadlock).
- The application read exposes `created_by_actor_id` and, via a `LATERAL` join, the latest approval's
  `status_code` + last `decision_code` — so the UI derives a **display** review status (Draft / In
  review / Rejected / Changes requested) for a pending app. No persisted status codes added.

## Deferred (NOT touched)

`risk_reclassification` / `business_change` change-proposal kinds + impacted-asset selection +
draft-fork (FR-IN-013); asset linking / promotion gate (FR-IN-009); the assessment-justification
completeness gate (FR-AS-010).
