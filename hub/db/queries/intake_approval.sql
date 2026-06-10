-- Intake approval (Slice 4): the per-intake reads needed to gate submit and compute the FR-IN-005
-- tier quorum. The approval request/sign-off rows themselves live in the shared approval.sql
-- primitive. Raw SQL, no ORM (ADR-0012).

-- name: get_intake_tier_status^
-- The tier (drives the quorum) + status (gates submit). Null tier => not yet classified (-> 400).
SELECT ai_risk_tier_code, intake_status_code FROM core.intake WHERE intake_id = %(intake_id)s;

-- name: has_open_intake_approval^
-- True if a pending kind=intake approval already exists for this intake (duplicate -> 409).
SELECT EXISTS (
    SELECT 1 FROM core.approval_request
    WHERE target_intake_id = %(intake_id)s AND request_kind_code = 'intake' AND status_code = 'pending'
) AS present;

-- name: cancel_pending_intake_approvals!
-- Supersede any still-open kind=intake approval for an intake — the requester withdrawing their
-- submission (mirrors cancel_pending_application_approvals). The intake's own status is left
-- unchanged (as application withdraw leaves the app 'pending'); it drops back to a revisable draft.
UPDATE core.approval_request SET status_code = 'cancelled', updated_at = now()
WHERE target_intake_id = %(intake_id)s AND request_kind_code = 'intake' AND status_code = 'pending';
