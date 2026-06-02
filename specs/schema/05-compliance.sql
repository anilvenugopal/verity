-- =====================================================================
-- 05-compliance.sql — Verity v2 hardened schema · core COMPLIANCE (ADR-0008)
-- The three-axis, two-bridge control/evidence metamodel. Per D7: ALL evolving
-- axes are EFFECTIVE-DATED (SCD-2 versions; valid_from/valid_to) so any past
-- obligation/evidence resolves "as-of". evidence (the fact stream) is Tier-2 and
-- lives in the audit domain (06). Compliance FKs from intake are wired at the end.
--
-- SCD-2 pattern here: <table>_id uuid PK = one VERSION row; <thing>_code = the stable
-- logical key; valid_from/valid_to (NULL = current). A partial unique on the code WHERE
-- valid_to IS NULL guarantees one current version. FKs reference the version surrogate,
-- which PINS the as-of version (reproducibility, ADR-0009).
-- =====================================================================

-- ===== LEFT AXIS: frameworks & provisions =============================
-- Framework identity is stable (one row + window); its PROVISIONS amend (SCD-2).
CREATE TABLE core.regulatory_framework (
    framework_code       text        NOT NULL,
    name                 text        NOT NULL,
    authority            text,                                  -- issuing body
    effective_start_date date        NOT NULL DEFAULT current_date,
    effective_end_date   date,
    created_at           timestamptz  NOT NULL DEFAULT now(),
    CONSTRAINT pk_regulatory_framework PRIMARY KEY (framework_code),
    CONSTRAINT ck_regulatory_framework_window CHECK (effective_end_date IS NULL OR effective_end_date >= effective_start_date));
COMMENT ON TABLE core.regulatory_framework IS 'tier:1. Left axis: a regulatory framework (NAIC, EU AI Act, SR 11-7…). Stable identity + validity window. ADR-0008.';

CREATE TABLE core.regulatory_provision (
    provision_id         uuid        NOT NULL DEFAULT uuidv7(),  -- a VERSION of the provision
    provision_code       text        NOT NULL,                   -- stable logical key
    framework_code       text        NOT NULL,
    citation             text        NOT NULL,                   -- e.g. "SR 11-7 §III.A"
    jurisdiction         text,
    text                 text,
    valid_from           timestamptz  NOT NULL DEFAULT now(),
    valid_to             timestamptz,
    created_at           timestamptz  NOT NULL DEFAULT now(),
    CONSTRAINT pk_regulatory_provision PRIMARY KEY (provision_id),
    CONSTRAINT fk_regulatory_provision_framework FOREIGN KEY (framework_code)
        REFERENCES core.regulatory_framework (framework_code) ON DELETE RESTRICT);
COMMENT ON TABLE core.regulatory_provision IS 'tier:1 SCD-2. Left axis: a citable provision within a framework; versions over time (amendments). ADR-0008/D7.';
CREATE UNIQUE INDEX uq_regulatory_provision_current ON core.regulatory_provision (provision_code) WHERE valid_to IS NULL;
CREATE INDEX ix_regulatory_provision_framework ON core.regulatory_provision (framework_code);

-- ===== CENTER AXIS: canonical requirements + cumulative tier ladder ===
CREATE TABLE core.canonical_requirement (
    requirement_id        uuid       NOT NULL DEFAULT uuidv7(),  -- a VERSION
    requirement_code      text       NOT NULL,                   -- stable logical key
    governance_domain_code text      NOT NULL,
    title                 text       NOT NULL,
    text                  text       NOT NULL,
    embedding             vector(384),                            -- similarity / semantic mapping (ADR-0009)
    valid_from            timestamptz NOT NULL DEFAULT now(),
    valid_to              timestamptz,
    created_at            timestamptz NOT NULL DEFAULT now(),
    CONSTRAINT pk_canonical_requirement PRIMARY KEY (requirement_id),
    CONSTRAINT fk_canonical_requirement_domain FOREIGN KEY (governance_domain_code)
        REFERENCES reference.governance_domain (code) ON DELETE RESTRICT);
COMMENT ON TABLE core.canonical_requirement IS 'tier:1 SCD-2. Center axis: the stable, technology-agnostic requirement vocabulary, grouped by governance_domain. Versions for as-of reproducibility. ADR-0008/D7.';
CREATE UNIQUE INDEX uq_canonical_requirement_current ON core.canonical_requirement (requirement_code) WHERE valid_to IS NULL;
CREATE INDEX ix_canonical_requirement_domain ON core.canonical_requirement (governance_domain_code);

CREATE TABLE core.requirement_tier (
    requirement_tier_id   uuid       NOT NULL DEFAULT uuidv7(),
    requirement_id        uuid       NOT NULL,                    -- the requirement version this tier belongs to
    tier_level            integer     NOT NULL,                   -- 1..N cumulative (tier N implies 1..N)
    title                 text       NOT NULL,
    criteria              text       NOT NULL,
    valid_from            timestamptz NOT NULL DEFAULT now(),
    valid_to              timestamptz,
    created_at            timestamptz NOT NULL DEFAULT now(),
    CONSTRAINT pk_requirement_tier PRIMARY KEY (requirement_tier_id),
    CONSTRAINT fk_requirement_tier_requirement FOREIGN KEY (requirement_id)
        REFERENCES core.canonical_requirement (requirement_id) ON DELETE RESTRICT,
    CONSTRAINT ck_requirement_tier_level_positive CHECK (tier_level >= 1));
COMMENT ON TABLE core.requirement_tier IS 'tier:1 SCD-2. Cumulative tier ladder per canonical requirement (tier N implies all below). Variable depth per requirement. ADR-0008.';
CREATE UNIQUE INDEX uq_requirement_tier_current ON core.requirement_tier (requirement_id, tier_level) WHERE valid_to IS NULL;

-- ===== RIGHT AXIS: controls + evidence specifications =================
CREATE TABLE core.control (
    control_id            uuid       NOT NULL DEFAULT uuidv7(),   -- a VERSION
    control_code          text       NOT NULL,                    -- stable logical key
    title                 text       NOT NULL,
    control_phase_code    text       NOT NULL,                    -- design_time|deploy_time|static_model|execution
    control_type_code     text       NOT NULL,                    -- preventive|detective|corrective|directive
    enforcement_action_code text     NOT NULL,                    -- block|refuse|suppress_write|warn|log_only
    description           text,
    valid_from            timestamptz NOT NULL DEFAULT now(),
    valid_to              timestamptz,
    created_at            timestamptz NOT NULL DEFAULT now(),
    CONSTRAINT pk_control PRIMARY KEY (control_id),
    CONSTRAINT fk_control_phase FOREIGN KEY (control_phase_code) REFERENCES reference.control_phase (code),
    CONSTRAINT fk_control_type FOREIGN KEY (control_type_code) REFERENCES reference.control_type (code),
    CONSTRAINT fk_control_enforcement FOREIGN KEY (enforcement_action_code) REFERENCES reference.enforcement_action (code));
COMMENT ON TABLE core.control IS 'tier:1 SCD-2. Right axis: an enforcement control at a lifecycle phase. Versions as controls mature (D7). phase lives here (requirement_control derives it — resolves verification S4).';
CREATE UNIQUE INDEX uq_control_current ON core.control (control_code) WHERE valid_to IS NULL;

CREATE TABLE core.evidence_specification (
    evidence_specification_id uuid   NOT NULL DEFAULT uuidv7(),
    control_id            uuid       NOT NULL,
    evidence_artifact_type_code text NOT NULL,                    -- config_snapshot|model_card|…
    produced_by           text,                                   -- what produces it
    citable_as            text,                                   -- how it is cited in a dossier
    valid_from            timestamptz NOT NULL DEFAULT now(),
    valid_to              timestamptz,
    created_at            timestamptz NOT NULL DEFAULT now(),
    CONSTRAINT pk_evidence_specification PRIMARY KEY (evidence_specification_id),
    CONSTRAINT fk_evidence_spec_control FOREIGN KEY (control_id) REFERENCES core.control (control_id) ON DELETE RESTRICT,
    CONSTRAINT fk_evidence_spec_artifact_type FOREIGN KEY (evidence_artifact_type_code) REFERENCES reference.evidence_artifact_type (code));
COMMENT ON TABLE core.evidence_specification IS 'tier:1 SCD-2. The evidence a control must produce (artifact_type/produced_by/citable_as). The actual evidence facts are Tier-2 (audit.evidence, 06). ADR-0008.';

-- ===== BRIDGE 1: provision -> requirement (min-tier; effective-dated) =
CREATE TABLE core.provision_requirement (
    provision_requirement_id uuid    NOT NULL DEFAULT uuidv7(),
    provision_id          uuid       NOT NULL,                    -- pinned provision version
    requirement_id        uuid       NOT NULL,                    -- pinned requirement version
    min_tier_level        integer     NOT NULL DEFAULT 1,         -- minimum cumulative tier this provision demands
    derivation_method_code text      NOT NULL DEFAULT 'manual',   -- how the mapping was established (D9)
    valid_from            timestamptz NOT NULL DEFAULT now(),
    valid_to              timestamptz,
    created_at            timestamptz NOT NULL DEFAULT now(),
    CONSTRAINT pk_provision_requirement PRIMARY KEY (provision_requirement_id),
    CONSTRAINT fk_provreq_provision FOREIGN KEY (provision_id) REFERENCES core.regulatory_provision (provision_id) ON DELETE RESTRICT,
    CONSTRAINT fk_provreq_requirement FOREIGN KEY (requirement_id) REFERENCES core.canonical_requirement (requirement_id) ON DELETE RESTRICT,
    CONSTRAINT fk_provreq_method FOREIGN KEY (derivation_method_code) REFERENCES reference.derivation_method (code),
    CONSTRAINT ck_provreq_min_tier CHECK (min_tier_level >= 1));
COMMENT ON TABLE core.provision_requirement IS 'tier:1 SCD-2. Bridge 1: many-to-many provision->requirement with min-tier. Effective-dated (mappings change as regs are mapped). derivation_method = manual/reasoner/human-validated (ADR-0009).';

-- ===== BRIDGE 2: requirement-tier -> control (per tier/phase; effective-dated) =
CREATE TABLE core.requirement_control (
    requirement_control_id uuid      NOT NULL DEFAULT uuidv7(),
    requirement_tier_id   uuid       NOT NULL,                    -- which tier of which requirement
    control_id            uuid       NOT NULL,                    -- which control (phase derived from control)
    derivation_method_code text      NOT NULL DEFAULT 'manual',
    valid_from            timestamptz NOT NULL DEFAULT now(),
    valid_to              timestamptz,
    created_at            timestamptz NOT NULL DEFAULT now(),
    CONSTRAINT pk_requirement_control PRIMARY KEY (requirement_control_id),
    CONSTRAINT fk_reqctrl_tier FOREIGN KEY (requirement_tier_id) REFERENCES core.requirement_tier (requirement_tier_id) ON DELETE RESTRICT,
    CONSTRAINT fk_reqctrl_control FOREIGN KEY (control_id) REFERENCES core.control (control_id) ON DELETE RESTRICT,
    CONSTRAINT fk_reqctrl_method FOREIGN KEY (derivation_method_code) REFERENCES reference.derivation_method (code));
COMMENT ON TABLE core.requirement_control IS 'tier:1 SCD-2. Bridge 2: which controls satisfy a requirement at a tier (phase derived from control, not stored — resolves verification S4). Effective-dated.';

-- ===== EXCEPTIONS (first-class audit; status mutable per D4) ==========
-- Renamed from reserved word `exception` -> compliance_exception (verification #7).
CREATE TABLE core.compliance_exception (
    compliance_exception_id uuid     NOT NULL DEFAULT uuidv7(),
    canonical_requirement_id uuid    NOT NULL,                    -- the requirement being excepted
    waived_tier_level     integer     NOT NULL,                   -- the tier waived
    scope_intake_id       uuid,                                    -- optional scope
    scope_application_id  uuid,
    exception_status_code text        NOT NULL DEFAULT 'requested',-- mutable (D4); transitions -> audit.status_transition
    approver_actor_id     uuid,                                    -- approve_exception action (compliance/security)
    signed_as_role_code   text,
    compensating_controls text        NOT NULL,                   -- what mitigates in the interim
    rationale             text        NOT NULL,
    expires_at            timestamptz  NOT NULL,                   -- max permitted duration
    opened_by_actor_id    uuid        NOT NULL,
    opened_role_code      text        NOT NULL,
    created_at            timestamptz  NOT NULL DEFAULT now(),
    updated_at            timestamptz  NOT NULL DEFAULT now(),
    CONSTRAINT pk_compliance_exception PRIMARY KEY (compliance_exception_id),
    CONSTRAINT fk_compliance_exception_requirement FOREIGN KEY (canonical_requirement_id) REFERENCES core.canonical_requirement (requirement_id) ON DELETE RESTRICT,
    CONSTRAINT fk_compliance_exception_intake FOREIGN KEY (scope_intake_id) REFERENCES core.intake (intake_id) ON DELETE RESTRICT,
    CONSTRAINT fk_compliance_exception_application FOREIGN KEY (scope_application_id) REFERENCES core.application (application_id) ON DELETE RESTRICT,
    CONSTRAINT fk_compliance_exception_status FOREIGN KEY (exception_status_code) REFERENCES reference.exception_status (code),
    CONSTRAINT fk_compliance_exception_approver FOREIGN KEY (approver_actor_id) REFERENCES core.actor (actor_id),
    CONSTRAINT fk_compliance_exception_signed_role FOREIGN KEY (signed_as_role_code) REFERENCES reference.role (code),
    CONSTRAINT fk_compliance_exception_opened_by FOREIGN KEY (opened_by_actor_id) REFERENCES core.actor (actor_id),
    CONSTRAINT fk_compliance_exception_opened_role FOREIGN KEY (opened_role_code) REFERENCES reference.role (code),
    CONSTRAINT ck_compliance_exception_tier CHECK (waived_tier_level >= 1));
COMMENT ON TABLE core.compliance_exception IS 'tier:1 first-class audit. A controlled, time-boxed waiver of a requirement tier: compensating controls, named approver (approve_exception), expiry. status mutable (D4); approving role = compliance/security. ADR-0008.';
CREATE INDEX ix_compliance_exception_requirement ON core.compliance_exception (canonical_requirement_id);
CREATE INDEX ix_compliance_exception_expiry ON core.compliance_exception (expires_at) WHERE exception_status_code = 'approved';

-- ===== DOMAIN MATURITY (append-only snapshots per D7) =================
CREATE TABLE core.domain_maturity (
    domain_maturity_id    uuid       NOT NULL DEFAULT uuidv7(),
    governance_domain_code text      NOT NULL,
    application_id        uuid,                                    -- scope (NULL = platform-wide)
    score                 numeric(5,2) NOT NULL,                  -- normalized 0..100 (algorithm in component spec)
    max_tier_achieved     integer,
    coverage_level_code   text,
    computed_at           timestamptz  NOT NULL DEFAULT now(),
    CONSTRAINT pk_domain_maturity PRIMARY KEY (domain_maturity_id),
    CONSTRAINT fk_domain_maturity_domain FOREIGN KEY (governance_domain_code) REFERENCES reference.governance_domain (code),
    CONSTRAINT fk_domain_maturity_application FOREIGN KEY (application_id) REFERENCES core.application (application_id) ON DELETE RESTRICT,
    CONSTRAINT fk_domain_maturity_coverage FOREIGN KEY (coverage_level_code) REFERENCES reference.coverage_level (code));
COMMENT ON TABLE core.domain_maturity IS 'tier:1 append-only. Per-domain normalized maturity score snapshots (trend history). Latest via domain_maturity_current. D7.';
CREATE INDEX ix_domain_maturity_domain_time ON core.domain_maturity (governance_domain_code, application_id, computed_at DESC);

CREATE VIEW core.domain_maturity_current AS
SELECT DISTINCT ON (governance_domain_code, application_id)
       governance_domain_code, application_id, score, max_tier_achieved, coverage_level_code, computed_at
FROM   core.domain_maturity
ORDER  BY governance_domain_code, application_id, computed_at DESC;

-- ===== wire deferred intake_obligation FKs (from 04-intake) ===========
ALTER TABLE core.intake_obligation
    ADD CONSTRAINT fk_intake_obligation_requirement
    FOREIGN KEY (canonical_requirement_id) REFERENCES core.canonical_requirement (requirement_id) ON DELETE RESTRICT;
ALTER TABLE core.intake_obligation
    ADD CONSTRAINT fk_intake_obligation_domain
    FOREIGN KEY (governance_domain_code) REFERENCES reference.governance_domain (code) ON DELETE RESTRICT;
ALTER TABLE core.intake_obligation
    ADD CONSTRAINT fk_intake_obligation_target_tier
    FOREIGN KEY (target_requirement_tier_id) REFERENCES core.requirement_tier (requirement_tier_id) ON DELETE RESTRICT;
