-- core.actor_role_grant  ·  subject: identity  ·  (table)

-- D4: append-only; current roles = view over latest event. is_primary flags the
-- default capacity (one current primary per actor; enforced in-app + via the view).
CREATE TABLE core.actor_role_grant (
    actor_role_grant_id uuid        NOT NULL DEFAULT uuidv7(),
    actor_id            uuid        NOT NULL,
    role_code           text        NOT NULL,
    is_primary          boolean      NOT NULL DEFAULT false,
    is_revocation       boolean      NOT NULL DEFAULT false,
    granted_by_actor_id uuid        NOT NULL,         -- server-resolved (D6)
    acting_role_code    text        NOT NULL,         -- capacity the granter acted in (D6)
    reason              text,
    created_at          timestamptz  NOT NULL DEFAULT now(),
    CONSTRAINT pk_actor_role_grant PRIMARY KEY (actor_role_grant_id),
    CONSTRAINT fk_actor_role_grant_actor FOREIGN KEY (actor_id)
        REFERENCES core.actor (actor_id) ON DELETE RESTRICT,
    CONSTRAINT fk_actor_role_grant_role FOREIGN KEY (role_code)
        REFERENCES reference.role (code) ON DELETE RESTRICT,
    CONSTRAINT fk_actor_role_grant_granted_by FOREIGN KEY (granted_by_actor_id)
        REFERENCES core.actor (actor_id) ON DELETE RESTRICT,
    CONSTRAINT fk_actor_role_grant_acting_role FOREIGN KEY (acting_role_code)
        REFERENCES reference.role (code) ON DELETE RESTRICT
);
COMMENT ON TABLE core.actor_role_grant IS 'tier:1 append-only. Platform-role grant/revoke events per actor; is_primary = default capacity. Current state via current_actor_role. D4/D6.';
CREATE INDEX ix_actor_role_grant_actor_role_time
    ON core.actor_role_grant (actor_id, role_code, created_at DESC);
