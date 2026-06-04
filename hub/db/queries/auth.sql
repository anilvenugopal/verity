-- Auth / identity queries (user-authentication.md) over the canonical schema:
-- core.actor (supertype) + core.account_user (human subtype) + core.actor_role_grant
-- + core.current_actor_role (view) + audit.auth_event.

-- name: provision_actor^
-- JIT provisioning (FR-006a). Returns actor_id for (tenant_id, microsoft_oid), creating the
-- human actor + account_user subtype if absent, and refreshing display fields on each login.
-- A concurrent first-login may unique-violate account_user; the caller retries (-> existing path).
WITH existing AS (
    SELECT actor_id FROM core.account_user
    WHERE tenant_id = %(tenant_id)s AND microsoft_oid = %(microsoft_oid)s
), upd AS (
    UPDATE core.account_user
       SET email = %(email)s, upn = %(upn)s, updated_at = now()
     WHERE tenant_id = %(tenant_id)s AND microsoft_oid = %(microsoft_oid)s
), ins_actor AS (
    INSERT INTO core.actor (actor_type_code, display_name)
    SELECT 'human', %(display_name)s WHERE NOT EXISTS (SELECT 1 FROM existing)
    RETURNING actor_id
), ins_user AS (
    INSERT INTO core.account_user (actor_id, tenant_id, microsoft_oid, email, upn)
    SELECT actor_id, %(tenant_id)s, %(microsoft_oid)s, %(email)s, %(upn)s FROM ins_actor
    RETURNING actor_id
)
SELECT actor_id FROM existing
UNION ALL
SELECT actor_id FROM ins_user;

-- name: get_account_state^
-- Account state for the fail-closed checks (FR-021): disabled_at + session_epoch.
SELECT actor_id, session_epoch, disabled_at
FROM   core.account_user
WHERE  tenant_id = %(tenant_id)s AND microsoft_oid = %(microsoft_oid)s;

-- name: get_platform_roles
-- Effective platform roles (latest non-revoked grant per role). Read from PRIMARY for authz.
SELECT role_code FROM core.current_actor_role WHERE actor_id = %(actor_id)s;

-- name: has_role_grant^
SELECT EXISTS (
    SELECT 1 FROM core.current_actor_role
    WHERE actor_id = %(actor_id)s AND role_code = %(role_code)s
) AS present;

-- name: grant_platform_role!
-- DEV/MOCK seeding ONLY: ensure the mock principal's configured roles exist as grants so role
-- resolution runs through the real path. NOT the governed grant path (FR-023).
INSERT INTO core.actor_role_grant (actor_id, role_code, granted_by_actor_id, acting_role_code, reason)
VALUES (%(actor_id)s, %(role_code)s, %(granted_by)s, 'security', 'mock-auth dev seed');

-- name: bump_session_epoch!
-- FR-015: bump on any grant/revoke to force re-authorization.
UPDATE core.account_user SET session_epoch = session_epoch + 1, updated_at = now()
WHERE actor_id = %(actor_id)s;

-- name: insert_auth_event!
-- FR-024: append-only audit; written best-effort, never blocks/fails-open the request path.
INSERT INTO audit.auth_event (event_type, outcome, reason_code, actor_id, action_code, resource, request_id, ip)
VALUES (%(event_type)s, %(outcome)s, %(reason_code)s, %(actor_id)s, %(action_code)s, %(resource)s, %(request_id)s, %(ip)s);
