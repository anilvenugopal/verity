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
COMMENT ON TABLE core.actor_app_role_grant IS 'tier:1 append-only. Per-application app-team role grants (app_demo_*). Current via current_actor_app_role. D6.';
CREATE INDEX ix_actor_app_grant_actor_app_role_time
    ON core.actor_app_role_grant (actor_id, application_id, app_team_role_code, created_at DESC);
