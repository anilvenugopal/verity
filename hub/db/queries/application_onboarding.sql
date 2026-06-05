-- core.application — governed onboarding (propose) + reads (onboarding slice, US1).
-- Raw SQL, no ORM (ADR-0012). Propose creates the application PENDING (FR-IN-015); attribution
-- (created_by_actor_id, created_role_code) is server-resolved (D6). The compliance perimeter rows
-- live in application_perimeter.sql; the business owner's app_owner grant is written on approval (US2).

-- name: propose_application^
INSERT INTO core.application (
    code, name, description, application_status_code, line_of_business_code,
    data_classification_code, business_owner_actor_id,
    affects_consumers, processes_pii, consumer_facing,
    created_by_actor_id, created_role_code)
VALUES (
    %(code)s, %(name)s, %(description)s, 'pending', %(line_of_business_code)s,
    %(data_classification_code)s, %(business_owner_actor_id)s,
    %(affects_consumers)s, %(processes_pii)s, %(consumer_facing)s,
    %(created_by_actor_id)s, %(created_role_code)s)
RETURNING application_id, code, name, description, application_status_code, line_of_business_code,
          data_classification_code, business_owner_actor_id,
          affects_consumers, processes_pii, consumer_facing, created_at;

-- name: get_application^
SELECT application_id, code, name, description, application_status_code, line_of_business_code,
       data_classification_code, business_owner_actor_id,
       affects_consumers, processes_pii, consumer_facing, created_at
FROM core.application
WHERE application_id = %(application_id)s;

-- name: get_application_gate^
-- The fields needed to gate submit + compute the onboarding quorum (US2): status, the designated
-- owner, and the proposer (created_by). owner != proposer => the business owner must also approve.
SELECT application_status_code, business_owner_actor_id, created_by_actor_id
FROM core.application
WHERE application_id = %(application_id)s;

-- name: set_application_status!
-- Governed lifecycle transition (US3): active<->suspended, active/suspended->retired. The legal
-- set is enforced in the service; pending->active happens only via onboarding approval (US2).
UPDATE core.application SET application_status_code = %(status_code)s, updated_at = now()
WHERE application_id = %(application_id)s;

-- name: list_applications
SELECT application_id, code, name, description, application_status_code, line_of_business_code,
       data_classification_code, business_owner_actor_id,
       affects_consumers, processes_pii, consumer_facing, created_at
FROM core.application
ORDER BY created_at DESC;
