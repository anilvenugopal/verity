-- core.intake — create + reads (intake slice, US1).
-- Raw SQL, no ORM (ADR-0012). intake_status_code defaults to 'proposed' (DB default); the
-- classification codes are left null here (set later via /classification, US2). Attribution is
-- server-resolved (D6 / FR-018). Classification + status-change statements arrive with US2/US3.

-- name: create_intake^
-- application_id is bound by the router after confirming the parent exists (404 otherwise); the
-- FK is the backstop. Returns the full API view of the new intake.
INSERT INTO core.intake (application_id, title, description, created_by_actor_id, created_role_code)
VALUES (%(application_id)s, %(title)s, %(description)s, %(created_by_actor_id)s, %(created_role_code)s)
RETURNING intake_id, application_id, title, description, intake_status_code,
          ai_risk_tier_code, naic_materiality_code, materiality_tier_code, created_at;

-- name: get_intake^
SELECT intake_id, application_id, title, description, intake_status_code,
       ai_risk_tier_code, naic_materiality_code, materiality_tier_code, created_at
FROM core.intake
WHERE intake_id = %(intake_id)s;

-- name: list_intakes_by_application
SELECT intake_id, application_id, title, description, intake_status_code,
       ai_risk_tier_code, naic_materiality_code, materiality_tier_code, created_at
FROM core.intake
WHERE application_id = %(application_id)s
ORDER BY created_at DESC;

-- name: get_intake_status^
-- The current status, read inside the status-change transaction to capture from_code (D-INT-1).
-- Null => the intake does not exist (-> 404).
SELECT intake_status_code FROM core.intake WHERE intake_id = %(intake_id)s;

-- name: update_intake_status^
-- Move the status. The to-code is validated by fk_intake_status -> reference.intake_status; an
-- invalid code raises a FK violation the router maps to 400 (before any audit row is written).
UPDATE core.intake SET intake_status_code = %(to_status_code)s, updated_at = now()
WHERE intake_id = %(intake_id)s
RETURNING intake_id, application_id, title, description, intake_status_code,
          ai_risk_tier_code, naic_materiality_code, materiality_tier_code, created_at;

-- name: classify_intake^
-- Set/refresh risk tier + materiality (US2). Any subset: COALESCE leaves an unspecified (null
-- param) code unchanged; a supplied code overwrites. An invalid code trips its reference FK
-- (fk_intake_risk_tier / _naic / _materiality) — the router maps that to 400 (D-INT-7). Returns
-- null if the intake does not exist (no row updated) -> 404.
UPDATE core.intake SET
    ai_risk_tier_code     = COALESCE(%(ai_risk_tier_code)s, ai_risk_tier_code),
    naic_materiality_code = COALESCE(%(naic_materiality_code)s, naic_materiality_code),
    materiality_tier_code = COALESCE(%(materiality_tier_code)s, materiality_tier_code),
    updated_at = now()
WHERE intake_id = %(intake_id)s
RETURNING intake_id, application_id, title, description, intake_status_code,
          ai_risk_tier_code, naic_materiality_code, materiality_tier_code, created_at;
