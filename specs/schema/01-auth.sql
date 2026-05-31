-- 01-auth.sql — hardened v2 schema domain: auth
-- See ASSEMBLY-AND-VERIFICATION.md for cross-domain FKs & review items.

-- =============================================================================
-- DOMAIN: AUTH & IDENTITY  (v2-new; specs/features/user-authentication.md)
-- Service owner: verity-governance (ADR-0003). Tier-1 system-of-record for
-- identity + append-only role grants; Tier-2 for the auth_event audit log.
-- All objects live in schema "governance" (naming-conventions.md §2: never the
-- bare public schema). Append-only grants + current-state VIEWs (ADR-0005 rule 3).
--
-- PORTABILITY: uuidv7() assumes PostgreSQL 18+ (naming-conventions.md §3). On
-- earlier majors substitute a UUIDv7 generator (e.g. a pg_uuidv7 extension
-- function) bound to the same DEFAULT; no logic depends on key monotonicity
-- beyond index locality.
-- =============================================================================

CREATE SCHEMA IF NOT EXISTS governance;

-- -----------------------------------------------------------------------------
-- ENUMS
-- -----------------------------------------------------------------------------

-- platform_role: 10 values carried VERBATIM from v1 governance.studio_role.
-- The "approval_role" 7-member subset (business_owner, compliance, legal,
-- model_risk, ai_governance, security, privacy) is NOT a parallel enum; it is
-- enforced as a CHECK subset wherever sign-off authority is required, keeping a
-- single source of truth (spec Enums note; FR-009).
CREATE TYPE governance.platform_role AS ENUM (
    'business_owner',
    'compliance',
    'legal',
    'model_risk',
    'ai_governance',
    'security',
    'privacy',
    'engineer',
    'auditor',
    'viewer'
);
COMMENT ON TYPE governance.platform_role IS
    'tier:1 platform/governance role taxonomy; 10 values verbatim from v1 studio_role. Approval-capable subset = {business_owner,compliance,legal,model_risk,ai_governance,security,privacy}.';

-- app_team_role: 5 values, v2-NEW per-application authorization dimension.
CREATE TYPE governance.app_team_role AS ENUM (
    'app_demo_owner',
    'app_demo_sre',
    'app_demo_dev',
    'app_demo_lead',
    'app_demo_ops'
);
COMMENT ON TYPE governance.app_team_role IS
    'tier:1 v2-new per-application role dimension; scoped to application_id.';

-- auth_event_type / auth_event_outcome: closed value sets for the audit log.
-- Modeled as enums per naming-conventions.md §9 (preferred over CHECK-on-text);
-- the spec sketch used free text columns, hardened here to enums.
CREATE TYPE governance.auth_event_type AS ENUM (
    'login',
    'logout',
    'session_expiry',
    'session_termination',
    'authz_denial'
);
COMMENT ON TYPE governance.auth_event_type IS
    'tier:2 authentication/authorization event category.';

CREATE TYPE governance.auth_event_outcome AS ENUM (
    'success',
    'failure',
    'denied'
);
COMMENT ON TYPE governance.auth_event_outcome IS
    'tier:2 outcome of an auth_event.';

-- -----------------------------------------------------------------------------
-- TABLE: governance.app_user  (Tier-1 system-of-record; identity principal)
-- NB: spec names this "user"; "user" is a reserved word and naming-conventions
-- §1 forbids reserved-word identifiers, so the hardened name is "app_user".
-- See OPEN ISSUE. Identity is the IMMUTABLE composite (tenant_id, microsoft_oid)
-- as a UNIQUE constraint; never keyed on email (FR-005/FR-006).
-- -----------------------------------------------------------------------------
CREATE TABLE governance.app_user (
    app_user_id    uuid        NOT NULL DEFAULT uuidv7(),
    tenant_id      uuid        NOT NULL,                       -- Entra tid
    microsoft_oid  uuid        NOT NULL,                       -- Entra oid (immutable per tenant)
    display_name   text        NOT NULL,                       -- display only (mutable, non-key)
    email          text,                                       -- display only (mutable, non-key)
    upn            text,                                        -- display only (mutable, non-key)
    session_epoch  integer     NOT NULL DEFAULT 0,             -- bumped on any role change (FR-015)
    disabled_at    timestamptz,                                 -- non-null => fail closed on refresh (FR-021)
    created_at     timestamptz NOT NULL DEFAULT now(),
    updated_at     timestamptz NOT NULL DEFAULT now(),
    CONSTRAINT pk_app_user PRIMARY KEY (app_user_id),
    CONSTRAINT uq_app_user_tenant_oid UNIQUE (tenant_id, microsoft_oid),
    CONSTRAINT ck_app_user_session_epoch_nonneg CHECK (session_epoch >= 0)
);
COMMENT ON TABLE governance.app_user IS
    'tier:1 system-of-record identity principal. Natural key = (tenant_id, microsoft_oid). Display fields are point-in-time-unstable, display-only; audit reads bind to app_user_id only (FR-018). Created solely via atomic upsert on uq_app_user_tenant_oid (FR-006a).';
COMMENT ON COLUMN governance.app_user.disabled_at IS
    'Non-null fails the principal closed on next role refresh and terminates active sessions (FR-021).';
COMMENT ON COLUMN governance.app_user.session_epoch IS
    'Token/role version; bumped on any platform OR app-team grant/revoke to force re-authorization (FR-015).';

-- -----------------------------------------------------------------------------
-- TABLE: governance.platform_role_grant (Tier-1, APPEND-ONLY)
-- A revoke is a new row with is_revocation = true; current state is a VIEW over
-- the latest event per (app_user_id, role). No UPDATE/DELETE (FR-017, ADR-0005 §3).
-- -----------------------------------------------------------------------------
CREATE TABLE governance.platform_role_grant (
    platform_role_grant_id uuid                  NOT NULL DEFAULT uuidv7(),
    app_user_id            uuid                  NOT NULL,
    role                   governance.platform_role NOT NULL,
    is_revocation          boolean               NOT NULL DEFAULT false,
    granted_by             uuid                  NOT NULL,      -- server-resolved actor (FR-017); never client-supplied
    reason                 text,
    granted_at             timestamptz           NOT NULL DEFAULT now(),
    CONSTRAINT pk_platform_role_grant PRIMARY KEY (platform_role_grant_id),
    CONSTRAINT fk_platform_role_grant_app_user
        FOREIGN KEY (app_user_id) REFERENCES governance.app_user (app_user_id)
        ON DELETE RESTRICT,
    CONSTRAINT fk_platform_role_grant_actor
        FOREIGN KEY (granted_by)  REFERENCES governance.app_user (app_user_id)
        ON DELETE RESTRICT
);
COMMENT ON TABLE governance.platform_role_grant IS
    'tier:1 append-only platform-role grant/revoke event log. Revoke = new row (is_revocation=true). No in-place mutation; current state = governance.current_platform_role view (FR-017).';
COMMENT ON COLUMN governance.platform_role_grant.granted_by IS
    'Server-resolved app_user_id of the authenticated actor; MUST NOT be accepted from request body (FR-017). Self-escalation guard (granted_by != app_user_id for elevations) is enforced in the API layer (FR-023).';

-- Latest-event-per-subject lookup (drives effective-roles resolution; FR-014).
CREATE INDEX ix_platform_role_grant_latest
    ON governance.platform_role_grant (app_user_id, role, granted_at DESC);
-- FK index on the actor reference (naming-conventions.md §6).
CREATE INDEX ix_platform_role_grant_granted_by
    ON governance.platform_role_grant (granted_by);

-- -----------------------------------------------------------------------------
-- TABLE: governance.app_team_role_grant (Tier-1, APPEND-ONLY, v2-NEW)
-- Per-application dimension scoped to application_id (FR-010). Append-only;
-- current state per (application_id, app_user_id, role) via a VIEW.
-- FK to governance.application is declared but NOT VALID at seed time because
-- the PACKAGES/registry domain owns application and may be applied in a separate
-- migration; validate once application exists (see OPEN ISSUE).
-- -----------------------------------------------------------------------------
CREATE TABLE governance.app_team_role_grant (
    app_team_role_grant_id uuid                   NOT NULL DEFAULT uuidv7(),
    app_user_id            uuid                   NOT NULL,
    application_id         uuid                   NOT NULL,     -- server-derived scope (FR-010); never client-supplied
    role                   governance.app_team_role NOT NULL,
    is_revocation          boolean                NOT NULL DEFAULT false,
    granted_by             uuid                   NOT NULL,     -- server-resolved actor (FR-017)
    reason                 text,
    granted_at             timestamptz            NOT NULL DEFAULT now(),
    CONSTRAINT pk_app_team_role_grant PRIMARY KEY (app_team_role_grant_id),
    CONSTRAINT fk_app_team_role_grant_app_user
        FOREIGN KEY (app_user_id) REFERENCES governance.app_user (app_user_id)
        ON DELETE RESTRICT,
    CONSTRAINT fk_app_team_role_grant_actor
        FOREIGN KEY (granted_by)  REFERENCES governance.app_user (app_user_id)
        ON DELETE RESTRICT
    -- CONSTRAINT fk_app_team_role_grant_application
    --     FOREIGN KEY (application_id) REFERENCES governance.application (application_id)
    --     ON DELETE RESTRICT
    -- ^ deferred: governance.application is owned by the registry/packages domain;
    --   add + VALIDATE once that table exists in the canonical schema.
);
COMMENT ON TABLE governance.app_team_role_grant IS
    'tier:1 append-only v2-new app-team role grant/revoke event log, scoped to application_id. No v1 equivalent (v1 had a single session persona, no persistent user->role table). Current state = governance.current_app_team_role view (FR-010, FR-017).';
COMMENT ON COLUMN governance.app_team_role_grant.application_id IS
    'Scope of the grant; in authz decisions application_id is derived server-side from the target resource, never client-supplied (FR-010). FK to governance.application pending that table (see schema OPEN ISSUE).';

-- Latest-event-per-(app,subject,role) lookup (drives scoped effective-roles).
CREATE INDEX ix_app_team_role_grant_latest
    ON governance.app_team_role_grant (application_id, app_user_id, role, granted_at DESC);
CREATE INDEX ix_app_team_role_grant_granted_by
    ON governance.app_team_role_grant (granted_by);

-- -----------------------------------------------------------------------------
-- TABLE: governance.auth_event (Tier-2, APPEND-ONLY, RANGE-partitioned by month)
-- High-volume audit substrate (FR-024). Ingested via the API async/bulk path,
-- never inline on the request hot path; writes MUST NOT block or fail-open.
-- No FK to app_user (intentional): avoids a cross-tier write dependency on the
-- hot ingest path; user_id is nullable for pre-identity failures; integrity is
-- enforced at the API layer (spec).
-- Composite PK (auth_event_id, created_at) because the partition key must be
-- part of the PK for a RANGE-partitioned table.
-- -----------------------------------------------------------------------------
CREATE TABLE governance.auth_event (
    auth_event_id  uuid                        NOT NULL DEFAULT uuidv7(),
    event_type     governance.auth_event_type    NOT NULL,
    outcome        governance.auth_event_outcome NOT NULL,
    reason_code    text,                                       -- bad_signature | expired | nonce_mismatch | unknown_tenant | mock_auth | ...
    app_user_id    uuid,                                        -- nullable for pre-identity failures (no FK; Tier-2)
    action_code    text,                                        -- requested action on authz_denial
    resource       text,
    request_id     text                        NOT NULL,       -- correlation id (NFR-008)
    ip             inet,
    created_at     timestamptz                 NOT NULL DEFAULT now(),
    CONSTRAINT pk_auth_event PRIMARY KEY (auth_event_id, created_at)
) PARTITION BY RANGE (created_at);
COMMENT ON TABLE governance.auth_event IS
    'tier:2 append-only auth audit log; month-range-partitioned on created_at, BRIN on time, retention by partition DETACH/DROP. Ingested via async/bulk path; never blocks or fail-opens the request (FR-024). No FK to app_user by design (cross-tier hot-path avoidance); integrity at API layer.';

-- Per-subject time-ordered audit reads.
CREATE INDEX ix_auth_event_app_user_time
    ON governance.auth_event (app_user_id, created_at DESC);
-- Tier-2 BRIN on time (naming-conventions.md §8); UUIDv7 keeps inserts clustered
-- by time, which makes BRIN effective.
CREATE INDEX brin_auth_event_created_at
    ON governance.auth_event USING brin (created_at);

-- Seed partition (current month). Operational tooling rolls future partitions.
CREATE TABLE governance.auth_event_2026_05
    PARTITION OF governance.auth_event
    FOR VALUES FROM ('2026-05-01') TO ('2026-06-01');
COMMENT ON TABLE governance.auth_event_2026_05 IS
    'tier:2 monthly partition of governance.auth_event for 2026-05.';

-- -----------------------------------------------------------------------------
-- CURRENT-STATE VIEWS (latest grant/revoke event per subject; ADR-0005 §3)
-- Effective roles = rows WHERE is_revocation = false. Per the spec, these MUST
-- be read from the PRIMARY for authorization decisions (replica lag must not
-- silently grant a revoked role; FR-015 / distributed-scale notes).
-- -----------------------------------------------------------------------------
CREATE VIEW governance.current_platform_role AS
SELECT DISTINCT ON (g.app_user_id, g.role)
       g.app_user_id,
       g.role,
       g.is_revocation,
       g.granted_by,
       g.granted_at
FROM   governance.platform_role_grant AS g
ORDER  BY g.app_user_id, g.role, g.granted_at DESC;
COMMENT ON VIEW governance.current_platform_role IS
    'Latest platform-role event per (app_user_id, role). Effective roles = rows WHERE is_revocation=false. Read from PRIMARY for authz (FR-015).';

CREATE VIEW governance.current_app_team_role AS
SELECT DISTINCT ON (g.application_id, g.app_user_id, g.role)
       g.application_id,
       g.app_user_id,
       g.role,
       g.is_revocation,
       g.granted_by,
       g.granted_at
FROM   governance.app_team_role_grant AS g
ORDER  BY g.application_id, g.app_user_id, g.role, g.granted_at DESC;
COMMENT ON VIEW governance.current_app_team_role IS
    'Latest app-team-role event per (application_id, app_user_id, role). Effective roles = rows WHERE is_revocation=false; scoped to application_id (FR-010). Read from PRIMARY for authz (FR-015).';
