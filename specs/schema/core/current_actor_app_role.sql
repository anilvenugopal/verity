-- core.current_actor_app_role  ·  subject: intake  ·  (view)

CREATE VIEW core.current_actor_app_role AS
SELECT actor_id, application_id, app_team_role_code
FROM (
    SELECT DISTINCT ON (actor_id, application_id, app_team_role_code)
           actor_id, application_id, app_team_role_code, is_revocation
    FROM   core.actor_app_role_grant
    ORDER  BY actor_id, application_id, app_team_role_code, created_at DESC
) latest
WHERE NOT is_revocation;
COMMENT ON VIEW core.current_actor_app_role IS
'Effective per-application app-team roles per actor (the latest non-revoked grant). What the per-application authorization checks read (D6).

@tier 1
@lifecycle view
@subject intake
@decision D6';
