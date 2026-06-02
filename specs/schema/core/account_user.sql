-- core.account_user  ·  subject: identity  ·  (table)

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
