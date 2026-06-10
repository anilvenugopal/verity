-- core.approval_request + core.approval_signoff — the minimal, reusable approval primitive (US2).
-- Generic over kind/target; the per-kind quorum is computed by the caller (D-ONB-1). Onboarding
-- (kind=application_onboarding) targets an application and, on resolution, activates it + writes
-- the owner grant. Raw SQL, no ORM (ADR-0012).

-- name: open_request^
-- Generic: bind exactly one target (intake XOR application; the version target is opened by the
-- lifecycle slice). The ck_approval_request_one_target CHECK is the backstop.
INSERT INTO core.approval_request
    (request_kind_code, target_intake_id, target_application_id, opened_by_actor_id, opened_role_code)
VALUES (%(request_kind_code)s, %(target_intake_id)s, %(target_application_id)s,
        %(opened_by_actor_id)s, %(opened_role_code)s)
RETURNING approval_request_id, request_kind_code, status_code, target_intake_id, target_application_id,
          opened_by_actor_id, opened_role_code, created_at;

-- name: get_request^
SELECT approval_request_id, request_kind_code, status_code, target_intake_id, target_application_id,
       opened_by_actor_id, opened_role_code, created_at
FROM core.approval_request
WHERE approval_request_id = %(approval_request_id)s;

-- name: list_signoffs
SELECT approver_actor_id, signed_as_role_code, decision_code, comment, created_at
FROM core.approval_signoff
WHERE approval_request_id = %(approval_request_id)s
ORDER BY created_at;

-- name: insert_signoff!
INSERT INTO core.approval_signoff
    (approval_request_id, approver_actor_id, signed_as_role_code, decision_code, comment)
VALUES (%(approval_request_id)s, %(approver_actor_id)s, %(signed_as_role_code)s,
        %(decision_code)s, %(comment)s);

-- name: set_request_status!
UPDATE core.approval_request SET status_code = %(status_code)s, updated_at = now()
WHERE approval_request_id = %(approval_request_id)s;

-- name: list_pending_onboarding_approvals
-- Pending application-onboarding approvals + the data to compute "awaiting me": the app identity,
-- its owner + proposer (created_by), which role slots are already signed, and whether THIS actor
-- has signed. The per-principal eligibility filter (quorum + self-approval guard) is in the service.
SELECT ar.approval_request_id, ar.opened_by_actor_id,
       a.application_id, a.code, a.name, a.business_owner_actor_id, a.created_by_actor_id,
       coalesce(array_agg(s.signed_as_role_code) FILTER (WHERE s.signed_as_role_code IS NOT NULL), '{}') AS signed_roles,
       bool_or(s.approver_actor_id = %(actor_id)s) AS i_signed
FROM core.approval_request ar
JOIN core.application a ON a.application_id = ar.target_application_id
LEFT JOIN core.approval_signoff s ON s.approval_request_id = ar.approval_request_id
WHERE ar.request_kind_code = 'application_onboarding' AND ar.status_code = 'pending'
GROUP BY ar.approval_request_id, ar.opened_by_actor_id, a.application_id, a.code, a.name,
         a.business_owner_actor_id, a.created_by_actor_id
ORDER BY ar.created_at DESC;

-- name: cancel_pending_application_approvals!
-- Supersede any still-open approval for an application (e.g. when re-submitting after an edit) so a
-- stale review can't be acted on and the latest request is unambiguous.
UPDATE core.approval_request SET status_code = 'cancelled', updated_at = now()
WHERE target_application_id = %(application_id)s AND status_code = 'pending';

-- name: set_application_active!
UPDATE core.application SET application_status_code = 'active', updated_at = now()
WHERE application_id = %(application_id)s;

-- name: insert_app_owner_grant!
INSERT INTO core.actor_app_role_grant
    (actor_id, application_id, app_team_role_code, granted_by_actor_id, acting_role_code, reason)
VALUES (%(actor_id)s, %(application_id)s, 'app_owner', %(granted_by_actor_id)s,
        %(acting_role_code)s, 'owner grant on onboarding approval');
