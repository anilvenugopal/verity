-- Application compliance perimeter (FR-IN-017) + initial app-team grants — onboarding US1.
-- The perimeter join rows and the (non-owner) initial app-team grants are written at propose, in
-- the same transaction as the application insert. Bad reference codes trip the FKs -> 400 (D-ONB).

-- name: add_application_framework!
INSERT INTO core.application_regulatory_framework (application_id, framework_code, created_by_actor_id)
VALUES (%(application_id)s, %(framework_code)s, %(created_by_actor_id)s);

-- name: add_application_domain!
INSERT INTO core.application_governance_domain (application_id, governance_domain_code, created_by_actor_id)
VALUES (%(application_id)s, %(governance_domain_code)s, %(created_by_actor_id)s);

-- name: add_application_jurisdiction!
INSERT INTO core.application_jurisdiction (application_id, jurisdiction_code, created_by_actor_id)
VALUES (%(application_id)s, %(jurisdiction_code)s, %(created_by_actor_id)s);

-- name: list_application_frameworks
SELECT framework_code FROM core.application_regulatory_framework
WHERE application_id = %(application_id)s ORDER BY framework_code;

-- name: list_application_domains
SELECT governance_domain_code FROM core.application_governance_domain
WHERE application_id = %(application_id)s ORDER BY governance_domain_code;

-- name: list_application_jurisdictions
SELECT jurisdiction_code FROM core.application_jurisdiction
WHERE application_id = %(application_id)s ORDER BY jurisdiction_code;

-- name: add_app_team_grant!
-- Initial app-team grant (non-owner at propose; the owner's app_owner grant lands on approval).
INSERT INTO core.actor_app_role_grant
    (actor_id, application_id, app_team_role_code, granted_by_actor_id, acting_role_code, reason)
VALUES (%(actor_id)s, %(application_id)s, %(app_team_role_code)s, %(granted_by_actor_id)s,
        %(acting_role_code)s, 'initial app-team at onboarding');
