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
