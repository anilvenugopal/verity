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
SELECT approver_actor_id, signed_as_role_code, decision_code, comment
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

-- name: set_application_active!
UPDATE core.application SET application_status_code = 'active', updated_at = now()
WHERE application_id = %(application_id)s;

-- name: insert_app_owner_grant!
INSERT INTO core.actor_app_role_grant
    (actor_id, application_id, app_team_role_code, granted_by_actor_id, acting_role_code, reason)
VALUES (%(actor_id)s, %(application_id)s, 'app_owner', %(granted_by_actor_id)s,
        %(acting_role_code)s, 'owner grant on onboarding approval');
