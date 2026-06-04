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
