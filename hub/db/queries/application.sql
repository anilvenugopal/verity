-- core.application — onboarding + reads (intake slice, US1).
-- Raw SQL, no ORM (ADR-0012). Attribution (created_by_actor_id, created_role_code) is bound from
-- the server-resolved AuthContext (D6 / FR-018), never the request body.

-- name: create_application^
-- Onboard an application. Name is unique + non-blank (DB CHECK/UNIQUE); a duplicate raises a
-- unique violation the router maps to 409. Returns the row the API exposes.
INSERT INTO core.application (name, description, created_by_actor_id, created_role_code)
VALUES (%(name)s, %(description)s, %(created_by_actor_id)s, %(created_role_code)s)
RETURNING application_id, name, description, created_at;

-- (get_application / list_applications live in application_onboarding.sql — the full read with the
--  compliance perimeter + latest-approval review status. The earlier minimal copies were removed to
--  avoid duplicate aiosql query names.)

-- name: get_latest_application_approval^
-- The most recent approval request bound to an application (the onboarding approval). Lets the
-- application workspace surface the sign-off gate without the caller knowing the approval id.
SELECT approval_request_id
FROM core.approval_request
WHERE target_application_id = %(application_id)s
ORDER BY created_at DESC
LIMIT 1;

-- name: get_pending_application_approval^
-- The app's open (pending) approval, if any — used to confirm there is something to cancel.
SELECT approval_request_id FROM core.approval_request
WHERE target_application_id = %(application_id)s AND status_code = 'pending'
ORDER BY created_at DESC LIMIT 1;

-- ── Hard delete (security-only, pending apps; API maintenance) ───────────────────────────────────
-- Run in FK order inside one transaction: sign-offs → approvals → perimeter (clear_* in
-- application_perimeter.sql) → app-team grants → the application row.

-- name: delete_application_signoffs!
DELETE FROM core.approval_signoff
WHERE approval_request_id IN (SELECT approval_request_id FROM core.approval_request
                              WHERE target_application_id = %(application_id)s);

-- name: delete_application_approvals!
DELETE FROM core.approval_request WHERE target_application_id = %(application_id)s;

-- name: delete_application_grants!
DELETE FROM core.actor_app_role_grant WHERE application_id = %(application_id)s;

-- name: delete_application!
DELETE FROM core.application WHERE application_id = %(application_id)s;
