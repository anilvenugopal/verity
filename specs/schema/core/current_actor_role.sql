-- core.current_actor_role  ·  subject: identity  ·  (view)

-- current platform roles per actor: latest grant per (actor, role), not revoked
CREATE VIEW core.current_actor_role AS
SELECT actor_id, role_code, is_primary
FROM (
    SELECT DISTINCT ON (actor_id, role_code)
           actor_id, role_code, is_primary, is_revocation
    FROM   core.actor_role_grant
    ORDER  BY actor_id, role_code, created_at DESC
) latest
WHERE NOT is_revocation;
COMMENT ON VIEW core.current_actor_role IS 'Effective platform roles per actor (latest non-revoked grant per role). D4.';
