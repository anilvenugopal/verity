-- core.actor_app_role_grant  ·  subject: intake  ·  (table)

CREATE TABLE core.actor_app_role_grant (
    actor_app_role_grant_id uuid     NOT NULL DEFAULT uuidv7(),
    actor_id               uuid      NOT NULL,
    application_id         uuid      NOT NULL,
    app_team_role_code     text      NOT NULL,
    is_revocation          boolean    NOT NULL DEFAULT false,
    granted_by_actor_id    uuid      NOT NULL,
    acting_role_code       text      NOT NULL,
    reason                 text,
    created_at             timestamptz NOT NULL DEFAULT now(),
    CONSTRAINT pk_actor_app_role_grant PRIMARY KEY (actor_app_role_grant_id),
    CONSTRAINT fk_actor_app_grant_actor FOREIGN KEY (actor_id) REFERENCES core.actor (actor_id) ON DELETE RESTRICT,
    CONSTRAINT fk_actor_app_grant_application FOREIGN KEY (application_id) REFERENCES core.application (application_id) ON DELETE RESTRICT,
    CONSTRAINT fk_actor_app_grant_role FOREIGN KEY (app_team_role_code) REFERENCES reference.app_team_role (code),
    CONSTRAINT fk_actor_app_grant_granted_by FOREIGN KEY (granted_by_actor_id) REFERENCES core.actor (actor_id),
    CONSTRAINT fk_actor_app_grant_acting_role FOREIGN KEY (acting_role_code) REFERENCES reference.role (code));
COMMENT ON TABLE core.actor_app_role_grant IS
'The append-only per-application app-team role grant/revoke log (the app_demo_* roles). Mirrors the platform-role pattern but scoped to one application; current state is current_actor_app_role (D6).

@tier 1
@lifecycle append-only
@subject intake
@status reference.app_team_role
@decision D6';
CREATE INDEX ix_actor_app_grant_actor_app_role_time
    ON core.actor_app_role_grant (actor_id, application_id, app_team_role_code, created_at DESC);
COMMENT ON COLUMN core.actor_app_role_grant.actor_app_role_grant_id IS
'Identity of the grant/revoke event.';
COMMENT ON COLUMN core.actor_app_role_grant.actor_id IS
'The actor whose app-team role changes. @ref core.actor hard';
COMMENT ON COLUMN core.actor_app_role_grant.application_id IS
'The application the role is scoped to. @ref core.application hard';
COMMENT ON COLUMN core.actor_app_role_grant.app_team_role_code IS
'The app-team role granted or revoked. @status reference.app_team_role';
COMMENT ON COLUMN core.actor_app_role_grant.is_revocation IS
'True if this revokes rather than grants; the view filters these out.';
COMMENT ON COLUMN core.actor_app_role_grant.granted_by_actor_id IS
'Who performed the grant/revoke. @ref core.actor hard';
COMMENT ON COLUMN core.actor_app_role_grant.acting_role_code IS
'The capacity they acted in. @status reference.role';
COMMENT ON COLUMN core.actor_app_role_grant.reason IS
'Why the grant or revocation was made.';
COMMENT ON COLUMN core.actor_app_role_grant.created_at IS
'When the event occurred; ordering for current state.';
