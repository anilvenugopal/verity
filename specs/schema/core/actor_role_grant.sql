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
COMMENT ON TABLE core.actor_role_grant IS
'The append-only grant/revoke event log for platform roles. Roles are never edited in place; each grant or revocation is its own immutable fact, and current_actor_role projects the latest non-revoked grant per role. is_primary marks the actor''s default capacity (D4, D6).

@tier 1
@lifecycle append-only
@subject identity
@status reference.role
@decision D4
@decision D6';
CREATE INDEX ix_actor_role_grant_actor_role_time
    ON core.actor_role_grant (actor_id, role_code, created_at DESC);
COMMENT ON COLUMN core.actor_role_grant.actor_role_grant_id IS
'Identity of the grant/revoke event.';
COMMENT ON COLUMN core.actor_role_grant.actor_id IS
'The actor whose roles change. @ref core.actor hard';
COMMENT ON COLUMN core.actor_role_grant.role_code IS
'The platform role being granted or revoked. @status reference.role';
COMMENT ON COLUMN core.actor_role_grant.is_primary IS
'Marks this as the actors default capacity; one current primary per actor.';
COMMENT ON COLUMN core.actor_role_grant.is_revocation IS
'True if this event revokes the role rather than granting it; the current view filters these out.';
COMMENT ON COLUMN core.actor_role_grant.granted_by_actor_id IS
'Who performed the grant/revoke, server-resolved (D6). @ref core.actor hard';
COMMENT ON COLUMN core.actor_role_grant.acting_role_code IS
'The capacity the granter acted in (D6). @status reference.role';
COMMENT ON COLUMN core.actor_role_grant.reason IS
'Why the grant or revocation was made.';
COMMENT ON COLUMN core.actor_role_grant.created_at IS
'When the event occurred; the ordering key for the latest grant.';
