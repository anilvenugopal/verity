-- 04-compliance.sql — hardened v2 schema domain: compliance
-- See ASSEMBLY-AND-VERIFICATION.md for cross-domain FKs & review items.

-- =============================================================================
-- VERITY v2 HARDENED SCHEMA — DOMAIN: COMPLIANCE (ADR-0008)
-- Three-axis, two-bridge control/evidence metamodel.
--   Left   axis : regulatory_framework -> regulatory_provision
--   Center axis : governance_domain, canonical_requirement -> requirement_tier (cumulative)
--   Right  axis : control (type/phase/enforcement_action), evidence_specification
--   Bridge 1    : provision_requirement (min-tier)
--   Bridge 2    : requirement_control (per tier, per phase)
--   Audit facts : evidence (append-only, Tier-2), exception (append-only)
--   Maturity    : domain_maturity (per-domain, append-only score snapshots)
--
-- Conventions: ADR-0005 / naming-conventions.md.
--   snake_case; singular tables; surrogate PK <table>_id uuid DEFAULT uuidv7();
--   named pk_/fk_/uq_/ck_/ix_/brin_ constraints; timestamptz; enums as pg ENUM.
-- uuidv7(): requires PostgreSQL 18+. Fallback for <18: install pg_uuidv7 ext and
--   alias, or DEFAULT gen_random_uuid() (loses time-ordering / BRIN locality).
-- Tier-1 = system-of-record metamodel (thin Postgres, not partitioned).
-- Tier-2 = bulk append-only audit log (evidence): range-partitioned on created_at,
--   BRIN on created_at, never UPDATE/DELETE in place.
-- =============================================================================

CREATE SCHEMA IF NOT EXISTS compliance;

-- -----------------------------------------------------------------------------
-- ENUM TYPES  (v1 used inline CHECK(... IN ...); v2 promotes closed sets to enums)
-- -----------------------------------------------------------------------------

-- v2-NEW. Lifecycle phase at which a control fires (ADR-0008 four-phase model).
CREATE TYPE compliance.control_phase AS ENUM (
    'design_time',
    'deploy_time',
    'static_model',   -- replaces v1 "data-at-rest"; at-rest package/model artifact
    'execution'       -- replaces v1 "data-in-motion"; runtime harness
);

-- v2-NEW. What category of control this is.
CREATE TYPE compliance.control_type AS ENUM (
    'preventive',
    'detective',
    'corrective',
    'directive'
);

-- v2-NEW. What a control does when it fires against non-compliant activity.
CREATE TYPE compliance.enforcement_action AS ENUM (
    'block',              -- hard gate (design_time / deploy_time)
    'refuse',             -- execution-phase refusal
    'suppress_write',     -- execution-phase write-suppression
    'warn',
    'log_only'
);

-- v2-NEW. Form of an evidence artifact a control produces.
CREATE TYPE compliance.evidence_artifact_type AS ENUM (
    'config_snapshot',
    'model_card',
    'package_manifest',
    'approval_record',
    'test_result',
    'validation_report',
    'decision_log',
    'binding_resolution',
    'deployment_record',
    'document'
);

-- CHANGE of v1 provision_requirement_map.mapping_source CHECK -> enum (members verbatim).
CREATE TYPE compliance.mapping_source AS ENUM (
    'manual',
    'semantic_recommended',
    'human_validated'
);

-- KEEP of v1 requirement_coverage.coverage_level CHECK -> enum (members verbatim).
-- Retained for the analytics-mart coverage vocabulary (see open issues).
CREATE TYPE compliance.coverage_level AS ENUM (
    'full',
    'substantial',
    'partial',
    'gap'
);

-- v2-NEW. Append-only exception lifecycle state, projected via exception_current view.
CREATE TYPE compliance.exception_status AS ENUM (
    'requested',
    'approved',
    'rejected',
    'revoked',
    'expired'
);

-- =============================================================================
-- LEFT AXIS — regulatory frameworks & provisions  (KEEP from v1)
-- =============================================================================

-- Tier-1. KEEP (v1 compliance.regulatory_framework). Bitemporal validity preserved.
CREATE TABLE compliance.regulatory_framework (
    regulatory_framework_id  uuid        NOT NULL DEFAULT uuidv7(),
    code                     text        NOT NULL,
    name                     text        NOT NULL,
    jurisdiction             text        NOT NULL,
    version                  text,
    effective_date           date,
    valid_from               date        NOT NULL DEFAULT current_date,
    valid_to                 date        NOT NULL DEFAULT DATE '2099-12-31',
    source_url               text,
    description              text,
    sort_seq                 integer     NOT NULL DEFAULT 0,
    created_at               timestamptz NOT NULL DEFAULT now(),
    updated_at               timestamptz NOT NULL DEFAULT now(),
    CONSTRAINT pk_regulatory_framework PRIMARY KEY (regulatory_framework_id),
    CONSTRAINT uq_regulatory_framework_code UNIQUE (code),
    CONSTRAINT ck_regulatory_framework_valid_range CHECK (valid_from <= valid_to)
);
COMMENT ON TABLE compliance.regulatory_framework IS 'tier:1 system-of-record. Left axis: regulatory frameworks (KEEP from v1).';

-- Tier-1. KEEP (v1 compliance.regulatory_provision). embedding_model_id dropped here
-- (embedding_config lives outside this domain; see open issues / DEFER in mapping).
CREATE TABLE compliance.regulatory_provision (
    regulatory_provision_id  uuid        NOT NULL DEFAULT uuidv7(),
    regulatory_framework_id  uuid        NOT NULL,
    citation                 text        NOT NULL,
    title                    text        NOT NULL,
    provision_text           text,
    effective_date           date,
    valid_from               date        NOT NULL DEFAULT current_date,
    valid_to                 date        NOT NULL DEFAULT DATE '2099-12-31',
    sort_seq                 integer     NOT NULL DEFAULT 0,
    created_at               timestamptz NOT NULL DEFAULT now(),
    updated_at               timestamptz NOT NULL DEFAULT now(),
    CONSTRAINT pk_regulatory_provision PRIMARY KEY (regulatory_provision_id),
    CONSTRAINT fk_regulatory_provision_framework
        FOREIGN KEY (regulatory_framework_id)
        REFERENCES compliance.regulatory_framework (regulatory_framework_id)
        ON DELETE RESTRICT,
    CONSTRAINT uq_regulatory_provision_citation
        UNIQUE (regulatory_framework_id, citation),
    CONSTRAINT ck_regulatory_provision_valid_range CHECK (valid_from <= valid_to)
);
COMMENT ON TABLE compliance.regulatory_provision IS 'tier:1 system-of-record. Left axis: citable provisions within a framework (KEEP from v1; column "text" renamed provision_text to avoid reserved-word use).';
CREATE INDEX ix_regulatory_provision_framework
    ON compliance.regulatory_provision (regulatory_framework_id);

-- =============================================================================
-- CENTER AXIS — governance domains, canonical requirements, cumulative tiers
-- =============================================================================

-- Tier-1. CHANGE (v1 compliance.canonical_requirement_theme -> governance_domain).
-- ADR-0008 organizes canonical requirements by governance DOMAIN and scores maturity
-- per domain; v1's "theme" was pure grouping. Domain is the carry-forward + new role.
CREATE TABLE compliance.governance_domain (
    governance_domain_id  uuid        NOT NULL DEFAULT uuidv7(),
    code                  text        NOT NULL,
    name                  text        NOT NULL,
    description           text,
    sort_seq              integer     NOT NULL DEFAULT 0,
    created_at            timestamptz NOT NULL DEFAULT now(),
    updated_at            timestamptz NOT NULL DEFAULT now(),
    CONSTRAINT pk_governance_domain PRIMARY KEY (governance_domain_id),
    CONSTRAINT uq_governance_domain_code UNIQUE (code)
);
COMMENT ON TABLE compliance.governance_domain IS 'tier:1 system-of-record. Center axis grouping + unit of maturity scoring (CHANGE of v1 canonical_requirement_theme).';

-- Tier-1. KEEP (v1 compliance.canonical_requirement). Stable technology-agnostic vocab.
-- theme_id -> governance_domain_id (CHANGE). embedding_model_id DEFERred (see open issues).
CREATE TABLE compliance.canonical_requirement (
    canonical_requirement_id  uuid        NOT NULL DEFAULT uuidv7(),
    governance_domain_id      uuid        NOT NULL,
    code                      text        NOT NULL,
    title                     text        NOT NULL,
    description               text,
    sort_seq                  integer     NOT NULL DEFAULT 0,
    created_at                timestamptz NOT NULL DEFAULT now(),
    updated_at                timestamptz NOT NULL DEFAULT now(),
    CONSTRAINT pk_canonical_requirement PRIMARY KEY (canonical_requirement_id),
    CONSTRAINT fk_canonical_requirement_domain
        FOREIGN KEY (governance_domain_id)
        REFERENCES compliance.governance_domain (governance_domain_id)
        ON DELETE RESTRICT,
    CONSTRAINT uq_canonical_requirement_code UNIQUE (code)
);
COMMENT ON TABLE compliance.canonical_requirement IS 'tier:1 system-of-record. Center axis: stable, technology-agnostic requirement vocabulary (KEEP from v1; theme_id -> governance_domain_id).';
CREATE INDEX ix_canonical_requirement_domain
    ON compliance.canonical_requirement (governance_domain_id);

-- Tier-1. v2-NEW. Cumulative tier ladder per canonical requirement. Operating at
-- tier N implies tiers 1..N active. Variable depth: as many tiers as regulation/best
-- practice require. tier_level is the cumulative ordinal (1 = baseline).
CREATE TABLE compliance.requirement_tier (
    requirement_tier_id       uuid        NOT NULL DEFAULT uuidv7(),
    canonical_requirement_id  uuid        NOT NULL,
    tier_level                integer     NOT NULL,
    name                      text        NOT NULL,
    description               text,
    created_at                timestamptz NOT NULL DEFAULT now(),
    updated_at                timestamptz NOT NULL DEFAULT now(),
    CONSTRAINT pk_requirement_tier PRIMARY KEY (requirement_tier_id),
    CONSTRAINT fk_requirement_tier_requirement
        FOREIGN KEY (canonical_requirement_id)
        REFERENCES compliance.canonical_requirement (canonical_requirement_id)
        ON DELETE CASCADE,
    CONSTRAINT uq_requirement_tier_level
        UNIQUE (canonical_requirement_id, tier_level),
    CONSTRAINT ck_requirement_tier_level_positive CHECK (tier_level >= 1)
);
COMMENT ON TABLE compliance.requirement_tier IS 'tier:1 system-of-record. v2-NEW cumulative tier ladder per canonical requirement (tier N implies 1..N).';
CREATE INDEX ix_requirement_tier_requirement
    ON compliance.requirement_tier (canonical_requirement_id);

-- =============================================================================
-- RIGHT AXIS — controls & evidence specifications  (v2-NEW; replaces feature axis)
-- =============================================================================

-- Tier-1. v2-NEW. A control: type, lifecycle phase, enforcement action. Controls
-- block non-compliant activity at the phase where they operate.
CREATE TABLE compliance.control (
    control_id          uuid        NOT NULL DEFAULT uuidv7(),
    code                text        NOT NULL,
    name                text        NOT NULL,
    description         text,
    control_type        compliance.control_type        NOT NULL,
    phase               compliance.control_phase        NOT NULL,
    enforcement_action  compliance.enforcement_action   NOT NULL,
    is_active           boolean     NOT NULL DEFAULT true,
    sort_seq            integer     NOT NULL DEFAULT 0,
    created_at          timestamptz NOT NULL DEFAULT now(),
    updated_at          timestamptz NOT NULL DEFAULT now(),
    CONSTRAINT pk_control PRIMARY KEY (control_id),
    CONSTRAINT uq_control_code UNIQUE (code)
);
COMMENT ON TABLE compliance.control IS 'tier:1 system-of-record. v2-NEW right axis: enforcement control (type/phase/enforcement_action). Replaces v1 feature hierarchy.';
CREATE INDEX ix_control_phase ON compliance.control (phase);

-- Tier-1. v2-NEW. Evidence specification: what artifact a control must produce, who
-- produces it, and how it is citable. Each spec belongs to exactly one control.
CREATE TABLE compliance.evidence_specification (
    evidence_specification_id  uuid        NOT NULL DEFAULT uuidv7(),
    control_id                 uuid        NOT NULL,
    code                       text        NOT NULL,
    name                       text        NOT NULL,
    artifact_type              compliance.evidence_artifact_type NOT NULL,
    produced_by                text        NOT NULL,   -- enforcement point that emits it
    citable_as                 text,                   -- how it is referenced in audit
    description                text,
    created_at                 timestamptz NOT NULL DEFAULT now(),
    updated_at                 timestamptz NOT NULL DEFAULT now(),
    CONSTRAINT pk_evidence_specification PRIMARY KEY (evidence_specification_id),
    CONSTRAINT fk_evidence_specification_control
        FOREIGN KEY (control_id)
        REFERENCES compliance.control (control_id)
        ON DELETE RESTRICT,
    CONSTRAINT uq_evidence_specification_code UNIQUE (code)
);
COMMENT ON TABLE compliance.evidence_specification IS 'tier:1 system-of-record. v2-NEW: artifact_type/produced_by/citable_as spec for evidence a control produces.';
CREATE INDEX ix_evidence_specification_control
    ON compliance.evidence_specification (control_id);

-- =============================================================================
-- BRIDGE 1 — provision <-> canonical requirement, with MINIMUM TIER  (CHANGE)
-- =============================================================================

-- Tier-1. CHANGE (v1 compliance.provision_requirement_map -> provision_requirement).
-- Adds min_tier_level: the minimum cumulative tier this provision demands of the
-- canonical requirement. match_strength/confidence/mapping_source preserved.
CREATE TABLE compliance.provision_requirement (
    provision_requirement_id  uuid        NOT NULL DEFAULT uuidv7(),
    regulatory_provision_id   uuid        NOT NULL,
    canonical_requirement_id  uuid        NOT NULL,
    min_tier_level            integer     NOT NULL DEFAULT 1,
    match_strength            numeric(3,2) NOT NULL DEFAULT 1.00,
    confidence                numeric(3,2) NOT NULL DEFAULT 1.00,
    mapping_source            compliance.mapping_source NOT NULL DEFAULT 'manual',
    validated_by              text,
    validated_at              timestamptz,
    notes                     text,
    created_at                timestamptz NOT NULL DEFAULT now(),
    updated_at                timestamptz NOT NULL DEFAULT now(),
    CONSTRAINT pk_provision_requirement PRIMARY KEY (provision_requirement_id),
    CONSTRAINT fk_provision_requirement_provision
        FOREIGN KEY (regulatory_provision_id)
        REFERENCES compliance.regulatory_provision (regulatory_provision_id)
        ON DELETE CASCADE,
    CONSTRAINT fk_provision_requirement_requirement
        FOREIGN KEY (canonical_requirement_id)
        REFERENCES compliance.canonical_requirement (canonical_requirement_id)
        ON DELETE CASCADE,
    CONSTRAINT uq_provision_requirement
        UNIQUE (regulatory_provision_id, canonical_requirement_id),
    CONSTRAINT ck_provision_requirement_match_strength
        CHECK (match_strength > 0 AND match_strength <= 1),
    CONSTRAINT ck_provision_requirement_confidence
        CHECK (confidence >= 0 AND confidence <= 1),
    CONSTRAINT ck_provision_requirement_min_tier_positive
        CHECK (min_tier_level >= 1)
);
COMMENT ON TABLE compliance.provision_requirement IS 'tier:1 system-of-record. Bridge 1 (CHANGE of v1 provision_requirement_map): provision<->canonical requirement with min_tier_level. New regs insert by mapping.';
CREATE INDEX ix_provision_requirement_provision
    ON compliance.provision_requirement (regulatory_provision_id);
CREATE INDEX ix_provision_requirement_requirement
    ON compliance.provision_requirement (canonical_requirement_id);

-- =============================================================================
-- BRIDGE 2 — canonical requirement <-> control/evidence, PER TIER, PER PHASE
-- =============================================================================

-- Tier-1. v2-NEW. Wires a specific requirement_tier to a control (and optionally the
-- evidence specification it satisfies) at a given lifecycle phase. phase is denormalized
-- here for query convenience but must equal the control's own phase (enforced in app /
-- see open issues for a composite-FK alternative).
CREATE TABLE compliance.requirement_control (
    requirement_control_id     uuid        NOT NULL DEFAULT uuidv7(),
    requirement_tier_id        uuid        NOT NULL,
    control_id                 uuid        NOT NULL,
    evidence_specification_id  uuid,
    phase                      compliance.control_phase NOT NULL,
    is_required                boolean     NOT NULL DEFAULT true,
    notes                      text,
    created_at                 timestamptz NOT NULL DEFAULT now(),
    updated_at                 timestamptz NOT NULL DEFAULT now(),
    CONSTRAINT pk_requirement_control PRIMARY KEY (requirement_control_id),
    CONSTRAINT fk_requirement_control_tier
        FOREIGN KEY (requirement_tier_id)
        REFERENCES compliance.requirement_tier (requirement_tier_id)
        ON DELETE CASCADE,
    CONSTRAINT fk_requirement_control_control
        FOREIGN KEY (control_id)
        REFERENCES compliance.control (control_id)
        ON DELETE RESTRICT,
    CONSTRAINT fk_requirement_control_evidence_spec
        FOREIGN KEY (evidence_specification_id)
        REFERENCES compliance.evidence_specification (evidence_specification_id)
        ON DELETE RESTRICT,
    CONSTRAINT uq_requirement_control
        UNIQUE (requirement_tier_id, control_id, phase)
);
COMMENT ON TABLE compliance.requirement_control IS 'tier:1 system-of-record. Bridge 2 (v2-NEW): requirement tier <-> control/evidence spec, per tier per phase. Replaces v1 requirement_feature_link.';
CREATE INDEX ix_requirement_control_tier
    ON compliance.requirement_control (requirement_tier_id);
CREATE INDEX ix_requirement_control_control
    ON compliance.requirement_control (control_id);

-- =============================================================================
-- EVIDENCE — append-only audit fact  (Tier-2, range-partitioned, BRIN)
-- =============================================================================

-- Tier-2. v2-NEW. APPEND-ONLY. One immutable fact per evidence artifact produced by a
-- control, tied to canonical requirement + tier + phase + the entity/run that produced
-- it. Never UPDATE/DELETE in place. Range-partitioned monthly on created_at; BRIN.
-- entity_type/entity_id and run_id are cross-domain references validated in the app
-- layer (no DB FK to governance/runtime from this domain) — see open issues.
CREATE TABLE compliance.evidence (
    evidence_id                uuid        NOT NULL DEFAULT uuidv7(),
    canonical_requirement_id   uuid        NOT NULL,
    requirement_tier_id        uuid        NOT NULL,
    control_id                 uuid        NOT NULL,
    evidence_specification_id  uuid,
    phase                      compliance.control_phase NOT NULL,
    artifact_type              compliance.evidence_artifact_type NOT NULL,
    entity_type                text,        -- e.g. 'agent_version','task_version','package'
    entity_id                  uuid,        -- cross-domain ref (app-validated)
    run_id                     uuid,        -- cross-domain ref to runtime.execution_run
    artifact_uri               text,
    artifact_digest            text,        -- content hash for tamper-evidence
    payload                    jsonb,       -- captured/derived evidence detail
    produced_by                text        NOT NULL,
    produced_at                timestamptz NOT NULL DEFAULT now(),
    created_at                 timestamptz NOT NULL DEFAULT now(),
    CONSTRAINT pk_evidence PRIMARY KEY (evidence_id, created_at),
    CONSTRAINT fk_evidence_requirement
        FOREIGN KEY (canonical_requirement_id)
        REFERENCES compliance.canonical_requirement (canonical_requirement_id)
        ON DELETE RESTRICT,
    CONSTRAINT fk_evidence_tier
        FOREIGN KEY (requirement_tier_id)
        REFERENCES compliance.requirement_tier (requirement_tier_id)
        ON DELETE RESTRICT,
    CONSTRAINT fk_evidence_control
        FOREIGN KEY (control_id)
        REFERENCES compliance.control (control_id)
        ON DELETE RESTRICT,
    CONSTRAINT fk_evidence_specification
        FOREIGN KEY (evidence_specification_id)
        REFERENCES compliance.evidence_specification (evidence_specification_id)
        ON DELETE RESTRICT
) PARTITION BY RANGE (created_at);
COMMENT ON TABLE compliance.evidence IS 'tier:2 bulk-log append-only. v2-NEW immutable audit fact: requirement+tier+phase+entity/run. PK includes created_at for partition pruning. No UPDATE/DELETE.';

-- Initial monthly partition (current month); operational tooling rolls subsequent months.
CREATE TABLE compliance.evidence_2026_05
    PARTITION OF compliance.evidence
    FOR VALUES FROM ('2026-05-01') TO ('2026-06-01');
CREATE TABLE compliance.evidence_2026_06
    PARTITION OF compliance.evidence
    FOR VALUES FROM ('2026-06-01') TO ('2026-07-01');

CREATE INDEX brin_evidence_created_at
    ON compliance.evidence USING brin (created_at);
CREATE INDEX ix_evidence_requirement
    ON compliance.evidence (canonical_requirement_id, created_at DESC);
CREATE INDEX ix_evidence_entity
    ON compliance.evidence (entity_type, entity_id);
CREATE INDEX ix_evidence_run
    ON compliance.evidence (run_id);

-- =============================================================================
-- EXCEPTION — append-only governance record  (Tier-1 audit; current via view)
-- =============================================================================

-- Tier-1 (audit, append-only). v2-NEW. One immutable row per exception state event.
-- Carries waived tier, affected requirement, named approver, compensating controls,
-- and expiry. Status transitions are appended (new row), never updated in place;
-- exception_current projects the latest state per exception_key. approver_user_id is a
-- cross-domain ref to the auth user (app-validated) — see open issues.
CREATE TABLE compliance.exception (
    exception_id              uuid        NOT NULL DEFAULT uuidv7(),
    exception_key             uuid        NOT NULL,   -- stable id across status events
    canonical_requirement_id  uuid        NOT NULL,
    requirement_tier_id       uuid        NOT NULL,   -- the specific tier WAIVED
    entity_type               text,
    entity_id                 uuid,
    status                    compliance.exception_status NOT NULL,
    reason                    text        NOT NULL,
    compensating_controls     text        NOT NULL,
    approver_user_id          uuid,                   -- cross-domain auth ref (app-validated)
    approver_name             text,
    approver_role             text,
    requested_by              text        NOT NULL,
    expires_at                timestamptz,            -- maximum permitted duration
    created_at                timestamptz NOT NULL DEFAULT now(),
    CONSTRAINT pk_exception PRIMARY KEY (exception_id),
    CONSTRAINT fk_exception_requirement
        FOREIGN KEY (canonical_requirement_id)
        REFERENCES compliance.canonical_requirement (canonical_requirement_id)
        ON DELETE RESTRICT,
    CONSTRAINT fk_exception_tier
        FOREIGN KEY (requirement_tier_id)
        REFERENCES compliance.requirement_tier (requirement_tier_id)
        ON DELETE RESTRICT,
    CONSTRAINT ck_exception_approved_has_approver
        CHECK (status <> 'approved' OR approver_user_id IS NOT NULL OR approver_name IS NOT NULL),
    CONSTRAINT ck_exception_approved_has_expiry
        CHECK (status <> 'approved' OR expires_at IS NOT NULL)
);
COMMENT ON TABLE compliance.exception IS 'tier:1 append-only audit. v2-NEW first-class exception: waived tier, requirement, approver, compensating controls, expiry. Status events appended; current state via exception_current.';
CREATE INDEX ix_exception_key
    ON compliance.exception (exception_key, created_at DESC);
CREATE INDEX ix_exception_requirement
    ON compliance.exception (canonical_requirement_id);
CREATE INDEX ix_exception_expires
    ON compliance.exception (expires_at) WHERE expires_at IS NOT NULL;

-- Current-state projection: latest event per exception_key (ADR-0005 rule 3).
CREATE VIEW compliance.exception_current AS
SELECT DISTINCT ON (e.exception_key)
       e.exception_key,
       e.exception_id              AS latest_event_id,
       e.canonical_requirement_id,
       e.requirement_tier_id,
       e.entity_type,
       e.entity_id,
       e.status,
       e.reason,
       e.compensating_controls,
       e.approver_user_id,
       e.approver_name,
       e.approver_role,
       e.expires_at,
       e.created_at               AS status_at
FROM   compliance.exception AS e
ORDER  BY e.exception_key, e.created_at DESC;
COMMENT ON VIEW compliance.exception_current IS 'Current state per exception_key over append-only compliance.exception.';

-- =============================================================================
-- PER-DOMAIN MATURITY  (append-only score snapshots)
-- =============================================================================

-- Tier-1 (append-only). v2-NEW. Normalized maturity score per governance domain at a
-- point in time. Scores recomputed/appended; latest per domain via domain_maturity_current.
-- The normalization algorithm itself is deferred to the compliance component spec.
CREATE TABLE compliance.domain_maturity (
    domain_maturity_id    uuid        NOT NULL DEFAULT uuidv7(),
    governance_domain_id  uuid        NOT NULL,
    score                 numeric(5,4) NOT NULL,   -- normalized 0..1
    requirement_count     integer     NOT NULL DEFAULT 0,
    method                text        NOT NULL DEFAULT 'normalized_v1',
    detail                jsonb,
    computed_at           timestamptz NOT NULL DEFAULT now(),
    created_at            timestamptz NOT NULL DEFAULT now(),
    CONSTRAINT pk_domain_maturity PRIMARY KEY (domain_maturity_id),
    CONSTRAINT fk_domain_maturity_domain
        FOREIGN KEY (governance_domain_id)
        REFERENCES compliance.governance_domain (governance_domain_id)
        ON DELETE CASCADE,
    CONSTRAINT ck_domain_maturity_score_range CHECK (score >= 0 AND score <= 1)
);
COMMENT ON TABLE compliance.domain_maturity IS 'tier:1 append-only. v2-NEW per-domain normalized maturity score snapshots; latest via domain_maturity_current.';
CREATE INDEX ix_domain_maturity_domain
    ON compliance.domain_maturity (governance_domain_id, computed_at DESC);

CREATE VIEW compliance.domain_maturity_current AS
SELECT DISTINCT ON (m.governance_domain_id)
       m.governance_domain_id,
       m.domain_maturity_id,
       m.score,
       m.requirement_count,
       m.method,
       m.detail,
       m.computed_at
FROM   compliance.domain_maturity AS m
ORDER  BY m.governance_domain_id, m.computed_at DESC;
COMMENT ON VIEW compliance.domain_maturity_current IS 'Latest maturity score per governance domain over append-only compliance.domain_maturity.';
