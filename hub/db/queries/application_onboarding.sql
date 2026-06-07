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
          data_classification_code, business_owner_actor_id, created_by_actor_id,
          affects_consumers, processes_pii, consumer_facing, created_at;

-- name: get_application^
-- Includes the latest approval's status + last decision (LATERAL) so the UI can derive a review
-- status (Draft / In review / Rejected / Changes requested) for a still-pending application.
SELECT a.application_id, a.code, a.name, a.description, a.application_status_code, a.line_of_business_code,
       a.data_classification_code, a.business_owner_actor_id, a.created_by_actor_id,
       bo.display_name AS business_owner_name, cb.display_name AS created_by_name,
       a.affects_consumers, a.processes_pii, a.consumer_facing, a.created_at,
       ar.status_code AS latest_approval_status, sd.decision_code AS latest_decision
FROM core.application a
LEFT JOIN core.actor bo ON bo.actor_id = a.business_owner_actor_id
LEFT JOIN core.actor cb ON cb.actor_id = a.created_by_actor_id
LEFT JOIN LATERAL (SELECT status_code, approval_request_id FROM core.approval_request
                   WHERE target_application_id = a.application_id ORDER BY created_at DESC LIMIT 1) ar ON true
LEFT JOIN LATERAL (SELECT decision_code FROM core.approval_signoff
                   WHERE approval_request_id = ar.approval_request_id ORDER BY created_at DESC LIMIT 1) sd ON true
WHERE a.application_id = %(application_id)s;

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

-- name: update_application^
-- Edit a still-pending application in place (pre-activation remediation, e.g. after a rejection).
-- The status guard means an active/approved application is never edited this way (that is the
-- governed change-proposal flow). Returns the row, or nothing if it was not pending / not found.
UPDATE core.application SET
    code = %(code)s, name = %(name)s, description = %(description)s,
    line_of_business_code = %(line_of_business_code)s, data_classification_code = %(data_classification_code)s,
    business_owner_actor_id = %(business_owner_actor_id)s,
    affects_consumers = %(affects_consumers)s, processes_pii = %(processes_pii)s, consumer_facing = %(consumer_facing)s,
    updated_at = now()
WHERE application_id = %(application_id)s AND application_status_code = 'pending'
RETURNING application_id, code, name, description, application_status_code, line_of_business_code,
          data_classification_code, business_owner_actor_id, created_by_actor_id,
          affects_consumers, processes_pii, consumer_facing, created_at;

-- name: list_applications
SELECT a.application_id, a.code, a.name, a.description, a.application_status_code, a.line_of_business_code,
       a.data_classification_code, a.business_owner_actor_id, a.created_by_actor_id,
       bo.display_name AS business_owner_name, cb.display_name AS created_by_name,
       a.affects_consumers, a.processes_pii, a.consumer_facing, a.created_at,
       ar.status_code AS latest_approval_status, sd.decision_code AS latest_decision
FROM core.application a
LEFT JOIN core.actor bo ON bo.actor_id = a.business_owner_actor_id
LEFT JOIN core.actor cb ON cb.actor_id = a.created_by_actor_id
LEFT JOIN LATERAL (SELECT status_code, approval_request_id FROM core.approval_request
                   WHERE target_application_id = a.application_id ORDER BY created_at DESC LIMIT 1) ar ON true
LEFT JOIN LATERAL (SELECT decision_code FROM core.approval_signoff
                   WHERE approval_request_id = ar.approval_request_id ORDER BY created_at DESC LIMIT 1) sd ON true
ORDER BY a.created_at DESC;
