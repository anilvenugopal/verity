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
COMMENT ON TABLE core.actor IS 'tier:1. Unified attribution principal (human or automation). Single actor_id target for actor_id + acting_role_code across the schema. D6.';
CREATE INDEX ix_actor_type ON core.actor (actor_type_code);
