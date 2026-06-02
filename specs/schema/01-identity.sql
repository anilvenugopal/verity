-- =====================================================================
-- 01-identity.sql — Verity v2 hardened schema · core IDENTITY (actor model)
-- Re-applied per D6 (unified actor), D2 (UUIDv7), D1 (reference codes),
-- D3 (core schema), D4 (append-only grants + current view), D9 (provenance-ready).
-- The unified `actor` is the single attribution target for the whole schema:
--   every auditable record carries actor_id + acting_role_code -> reference.role.
-- =====================================================================

-- ===== actor (supertype) =============================================
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

-- ===== account_user (human subtype) ==================================
-- Microsoft Entra identity. Shares actor_id with the supertype (subtype PK = FK).
CREATE TABLE core.account_user (
    actor_id        uuid        NOT NULL,            -- = core.actor.actor_id
    tenant_id       uuid        NOT NULL,            -- Entra tid
    microsoft_oid   uuid        NOT NULL,            -- Entra oid (immutable per tenant)
    email           text,                            -- display-only (mutable, non-key)
    upn             text,                            -- display-only
    session_epoch   integer      NOT NULL DEFAULT 0, -- bumped on any role change (revocation)
    disabled_at     timestamptz,                     -- non-null => fail closed
    created_at      timestamptz  NOT NULL DEFAULT now(),
    updated_at      timestamptz  NOT NULL DEFAULT now(),
    CONSTRAINT pk_account_user PRIMARY KEY (actor_id),
    CONSTRAINT fk_account_user_actor FOREIGN KEY (actor_id)
        REFERENCES core.actor (actor_id) ON DELETE RESTRICT,
    CONSTRAINT uq_account_user_tenant_oid UNIQUE (tenant_id, microsoft_oid)
);
COMMENT ON TABLE core.account_user IS 'tier:1. Human actor subtype (Entra identity). Keyed on immutable (tenant_id, microsoft_oid); email/upn display-only. user-authentication.md.';

-- ===== automation_actor (machine subtype) ============================
-- Named automated processes (the harness/runtime per app, named jobs).
CREATE TABLE core.automation_actor (
    actor_id          uuid       NOT NULL,           -- = core.actor.actor_id
    automation_name   text       NOT NULL,           -- e.g. 'equity-research-runner'
    application_id    uuid,                            -- optional: app it acts on behalf of
                                                       -- (FK -> core.application added in the intake domain)
    created_at        timestamptz NOT NULL DEFAULT now(),
    updated_at        timestamptz NOT NULL DEFAULT now(),
    CONSTRAINT pk_automation_actor PRIMARY KEY (actor_id),
    CONSTRAINT fk_automation_actor_actor FOREIGN KEY (actor_id)
        REFERENCES core.actor (actor_id) ON DELETE RESTRICT,
    CONSTRAINT uq_automation_actor_name UNIQUE (automation_name)
);
COMMENT ON TABLE core.automation_actor IS 'tier:1. Automation actor subtype: named machine principal, optionally on behalf of an application. D6.';

-- ===== actor_role_grant (append-only platform-role grants) ===========
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

-- NOTE: app_team_role_grant (application-scoped) is added with the intake/application
-- domain (needs core.application). auth_event (Tier-2) is added in the audit domain.
