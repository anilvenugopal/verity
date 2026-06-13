-- core.actor  ·  subject: identity  ·  (table)

-- 01-identity.sql — Verity v2 hardened schema · core IDENTITY (actor model)
-- Re-applied per D6 (unified actor), D2 (UUIDv7), D1 (reference codes),
-- D3 (core schema), D4 (append-only grants + current view), D9 (provenance-ready).
-- The unified `actor` is the single attribution target for the whole schema:
--   every auditable record carries actor_id + acting_role_code -> reference.role.

-- One identity for humans AND automations. The shared-parent pattern (like
-- executable, D5): subtypes share the actor_id PK.
CREATE TABLE core.actor (
    actor_id            uuid        NOT NULL DEFAULT uuidv7(),
    actor_type_code     text        NOT NULL,                 -- human | automation
    display_name        text        NOT NULL,
    primary_role_code   text,                                  -- auto-selected default capacity (D6)
    is_active           boolean      NOT NULL DEFAULT true,
    created_at          timestamptz  NOT NULL DEFAULT now(),
    updated_at          timestamptz  NOT NULL DEFAULT now(),
    created_by_actor_id uuid,                                  -- NULL only for the bootstrap/system seed
    CONSTRAINT pk_actor PRIMARY KEY (actor_id),
    CONSTRAINT fk_actor_actor_type FOREIGN KEY (actor_type_code)
        REFERENCES reference.actor_type (code) ON DELETE RESTRICT,
    CONSTRAINT fk_actor_primary_role FOREIGN KEY (primary_role_code)
        REFERENCES reference.role (code) ON DELETE RESTRICT,
    CONSTRAINT fk_actor_created_by FOREIGN KEY (created_by_actor_id)
        REFERENCES core.actor (actor_id) ON DELETE RESTRICT,
    CONSTRAINT ck_actor_display_name_not_blank CHECK (length(btrim(display_name)) > 0)
);
COMMENT ON TABLE core.actor IS
'The single attribution principal for the whole platform — one identity model for humans and automations alike. Every auditable record in the schema points back to an actor_id plus the role it acted in, so "who did this, in what capacity" has exactly one answer everywhere. Humans and automations are subtypes that share this id (account_user, automation_actor) (D6).

@tier 1
@lifecycle mutable
@subject identity
@status reference.actor_type
@decision D6';
CREATE INDEX ix_actor_type ON core.actor (actor_type_code);
COMMENT ON COLUMN core.actor.actor_id IS
'The universal attribution id; every actor_id + acting_role_code pair across the schema resolves here.';
COMMENT ON COLUMN core.actor.actor_type_code IS
'human or automation — selects which subtype row (account_user vs automation_actor) carries the details. @status reference.actor_type';
COMMENT ON COLUMN core.actor.display_name IS
'Human-readable name for the principal; required non-blank.';
COMMENT ON COLUMN core.actor.primary_role_code IS
'The default capacity used when the actor does not name one (D6). @status reference.role';
COMMENT ON COLUMN core.actor.is_active IS
'Whether the principal may act; deactivating fails closed without deleting the attribution target.';
COMMENT ON COLUMN core.actor.created_at IS
'When the principal was created.';
COMMENT ON COLUMN core.actor.updated_at IS
'When the principal was last updated.';
COMMENT ON COLUMN core.actor.created_by_actor_id IS
'Who created this principal; null only for the bootstrap/system seed. @ref core.actor hard';
