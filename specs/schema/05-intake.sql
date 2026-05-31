-- 05-intake.sql — hardened v2 schema domain: intake
-- See ASSEMBLY-AND-VERIFICATION.md for cross-domain FKs & review items.

-- =====================================================================
-- VERITY v2 HARDENED SCHEMA — DOMAIN: INTAKE
-- ADR-0005 (schema hardening), ADR-0004 (tiering), ADR-0008 (compliance
-- obligation-set linkage), binding-grammar contract, naming-conventions.md.
--
-- Scope: application, intake, intake_requirement, intake_impact_assessment,
-- intake_risk (materiality/AI-risk lives on intake header), intake_entity_link,
-- intake_artifact_plan, intake_artifact_plan_estimate, intake_cost_envelope,
-- intake_roi_assessment, approval_request, approval_signoff (append-only),
-- and the v2-NEW obligation-set linkage intake_obligation_resolution /
-- intake_obligation (ADR-0008, FR-IN-014).
--
-- Keys: surrogate <table>_id uuid DEFAULT uuidv7() (PG18+ time-ordered).
--   FALLBACK (PG<18): create a uuidv7() SQL function backed by the pg_uuidv7
--   extension, or substitute gen_random_uuid() (pgcrypto) at deploy time. The
--   column default name uuidv7() is intentionally portable across that swap.
-- Tiering: every table is Tier-1 system-of-record (low-volume governance
--   metamodel) EXCEPT approval_signoff, which is an append-only audit fact
--   (still Tier-1 sized here; insert-only by rule). No Tier-2/partitioned
--   tables in this domain.
-- Cross-domain refs assumed defined by sibling domains (FKs declared here,
--   created when those tables exist): governance.canonical_requirement,
--   governance.governance_domain, governance.requirement_tier,
--   governance.model, governance.entity_version/agent_version/task_version,
--   governance.platform_role_grant approver (auth) — see notes.
-- =====================================================================

CREATE SCHEMA IF NOT EXISTS governance;

-- ---------------------------------------------------------------------
-- ENUM TYPES (verbatim controlled vocabularies from v1 intake contracts)
-- ---------------------------------------------------------------------

-- Intake workflow status (v1 governance.intake_status, verbatim).
CREATE TYPE governance.intake_status AS ENUM (
    'proposed', 'in_review', 'impact_assessment', 'approved',
    'in_build', 'live', 'rejected', 'retired'
);
COMMENT ON TYPE governance.intake_status IS 'tier:1 Intake workflow lifecycle (distinct from asset lifecycle_state); verbatim from v1.';

-- AI risk tier (v1 governance.ai_risk_tier, verbatim — EU-AI-Act-aligned).
CREATE TYPE governance.ai_risk_tier AS ENUM (
    'minimal', 'limited', 'high', 'unacceptable'
);

-- NAIC materiality (v1 governance.naic_materiality, verbatim).
CREATE TYPE governance.naic_materiality AS ENUM (
    'material', 'non_material'
);

-- Requirement kind (v1 governance.requirement_kind, verbatim).
CREATE TYPE governance.requirement_kind AS ENUM (
    'business', 'functional', 'non_functional', 'compliance'
);

-- Requirement status (v1 governance.requirement_status, verbatim).
CREATE TYPE governance.requirement_status AS ENUM (
    'draft', 'approved', 'implemented', 'verified', 'deprecated'
);

-- Requirement-to-entity relationship (v1 governance.requirement_relationship, verbatim).
CREATE TYPE governance.requirement_relationship AS ENUM (
    'implements', 'tests', 'monitors', 'informs'
);

-- Studio actor role (v1 governance.studio_role, verbatim).
CREATE TYPE governance.studio_role AS ENUM (
    'business_owner', 'compliance', 'legal', 'model_risk', 'ai_governance',
    'security', 'privacy', 'engineer', 'auditor', 'viewer'
);

-- Approval role (v1 governance.approval_role, verbatim — subset of studio_role).
CREATE TYPE governance.approval_role AS ENUM (
    'business_owner', 'compliance', 'legal', 'model_risk', 'ai_governance',
    'security', 'privacy'
);

-- Approval decision (v1 governance.approval_decision, verbatim).
CREATE TYPE governance.approval_decision AS ENUM (
    'approved', 'rejected', 'requested_changes', 'abstained'
);

-- Approval request kind (v1 governance.approval_request_kind, verbatim).
CREATE TYPE governance.approval_request_kind AS ENUM (
    'intake', 'risk_reclassification', 'promote_candidate',
    'promote_champion', 'retire'
);

-- Artifact plan status (v1 governance.artifact_plan_status, verbatim).
CREATE TYPE governance.artifact_plan_status AS ENUM (
    'proposed', 'in_progress', 'realized', 'cancelled'
);

-- HARDENING: v1 approval_request.status was a free varchar(20) default 'pending'.
-- Promoted to a named enum (ADR-0005 rule: closed value set => enum, not CHECK-on-text).
CREATE TYPE governance.approval_request_status AS ENUM (
    'pending', 'approved', 'rejected', 'cancelled'
);
COMMENT ON TYPE governance.approval_request_status IS 'tier:1 Hardened from v1 free-text approval_request.status.';

-- NOTE: governance.entity_type, governance.capability_type,
-- governance.materiality_tier are defined in the REGISTRY/core domain (verbatim
-- carryover). They are referenced below but not (re)created here.

-- ---------------------------------------------------------------------
-- TABLE: application  (Tier-1)  — v1 governance.application, hardened
-- ---------------------------------------------------------------------
CREATE TABLE governance.application (
    application_id   uuid        NOT NULL DEFAULT uuidv7(),
    name             text        NOT NULL,
    display_name     text        NOT NULL,
    description      text,
    created_at       timestamptz NOT NULL DEFAULT now(),
    updated_at       timestamptz NOT NULL DEFAULT now(),
    CONSTRAINT pk_application PRIMARY KEY (application_id),
    CONSTRAINT uq_application_name UNIQUE (name),
    CONSTRAINT ck_application_name_not_blank CHECK (length(btrim(name)) > 0)
);
COMMENT ON TABLE governance.application IS 'tier:1 system-of-record. Business application that owns intakes/use-cases.';

-- ---------------------------------------------------------------------
-- TABLE: intake  (Tier-1)  — v1 governance.intake, hardened
--   Header: one row per business-approved AI use case. Carries AI-risk tier
--   and NAIC materiality (the risk/materiality classification).
-- ---------------------------------------------------------------------
CREATE TABLE governance.intake (
    intake_id                       uuid        NOT NULL DEFAULT uuidv7(),
    application_id                  uuid        NOT NULL,
    code                            text        NOT NULL,
    title                           text        NOT NULL,
    problem_statement               text        NOT NULL,
    expected_benefit                text        NOT NULL,
    in_scope_decisions              text,
    out_of_scope_decisions          text,
    affected_populations            jsonb       NOT NULL DEFAULT '[]'::jsonb,
    business_owner_name             text        NOT NULL,
    business_owner_email            text,
    requesting_team                 text,
    ai_risk_tier                    governance.ai_risk_tier   NOT NULL,
    risk_classification_rationale   text        NOT NULL,
    naic_materiality                governance.naic_materiality NOT NULL,
    status                          governance.intake_status  NOT NULL DEFAULT 'proposed',
    hitl_strategy                   text,
    hitl_review_threshold           text,
    intake_at                       timestamptz NOT NULL DEFAULT now(),
    approved_at                     timestamptz,
    retired_at                      timestamptz,
    effective_date                  date,
    next_recertification_due        date,
    created_by                      text        NOT NULL,
    acting_as_role                  governance.studio_role,
    notes                           text,
    created_at                      timestamptz NOT NULL DEFAULT now(),
    updated_at                      timestamptz NOT NULL DEFAULT now(),
    CONSTRAINT pk_intake PRIMARY KEY (intake_id),
    CONSTRAINT fk_intake_application
        FOREIGN KEY (application_id)
        REFERENCES governance.application (application_id)
        ON DELETE RESTRICT,
    CONSTRAINT uq_intake_application_code UNIQUE (application_id, code),
    CONSTRAINT ck_intake_code_not_blank CHECK (length(btrim(code)) > 0),
    CONSTRAINT ck_intake_affected_populations_array
        CHECK (jsonb_typeof(affected_populations) = 'array'),
    CONSTRAINT ck_intake_approved_at_when_approved
        CHECK (status <> 'approved' OR approved_at IS NOT NULL),
    CONSTRAINT ck_intake_retired_at_when_retired
        CHECK (status <> 'retired' OR retired_at IS NOT NULL)
);
COMMENT ON TABLE governance.intake IS 'tier:1 system-of-record. Intake header: one AI use-case per row; carries AI-risk tier + NAIC materiality.';
CREATE INDEX ix_intake_application_id ON governance.intake (application_id);
CREATE INDEX ix_intake_status         ON governance.intake (status);
CREATE INDEX ix_intake_ai_risk_tier   ON governance.intake (ai_risk_tier);
CREATE INDEX ix_intake_owner_email    ON governance.intake (business_owner_email);

-- ---------------------------------------------------------------------
-- TABLE: intake_impact_assessment  (Tier-1)  — v1, hardened
--   Versioned impact assessment (required for limited/high tier).
-- ---------------------------------------------------------------------
CREATE TABLE governance.intake_impact_assessment (
    intake_impact_assessment_id  uuid        NOT NULL DEFAULT uuidv7(),
    intake_id                    uuid        NOT NULL,
    version                      integer     NOT NULL DEFAULT 1,
    data_sources                 jsonb       NOT NULL DEFAULT '[]'::jsonb,
    potential_harms              jsonb       NOT NULL DEFAULT '[]'::jsonb,
    mitigations                  jsonb       NOT NULL DEFAULT '[]'::jsonb,
    fairness_considerations      text,
    privacy_considerations       text,
    human_oversight_plan         text,
    completed_at                 timestamptz,
    completed_by                 text,
    notes                        text,
    created_at                   timestamptz NOT NULL DEFAULT now(),
    updated_at                   timestamptz NOT NULL DEFAULT now(),
    CONSTRAINT pk_intake_impact_assessment PRIMARY KEY (intake_impact_assessment_id),
    CONSTRAINT fk_intake_impact_assessment_intake
        FOREIGN KEY (intake_id)
        REFERENCES governance.intake (intake_id)
        ON DELETE CASCADE,
    CONSTRAINT uq_intake_impact_assessment_version UNIQUE (intake_id, version),
    CONSTRAINT ck_intake_impact_assessment_version_positive CHECK (version >= 1),
    CONSTRAINT ck_intake_impact_assessment_data_sources_array
        CHECK (jsonb_typeof(data_sources) = 'array'),
    CONSTRAINT ck_intake_impact_assessment_potential_harms_array
        CHECK (jsonb_typeof(potential_harms) = 'array'),
    CONSTRAINT ck_intake_impact_assessment_mitigations_array
        CHECK (jsonb_typeof(mitigations) = 'array')
);
COMMENT ON TABLE governance.intake_impact_assessment IS 'tier:1 system-of-record. Versioned impact assessment per intake (limited/high AI-risk).';
CREATE INDEX ix_intake_impact_assessment_intake_id
    ON governance.intake_impact_assessment (intake_id);

-- ---------------------------------------------------------------------
-- TABLE: intake_requirement  (Tier-1)  — v1, hardened
--   BR/FR/NFR/compliance requirements with optional embedding.
-- ---------------------------------------------------------------------
CREATE TABLE governance.intake_requirement (
    intake_requirement_id    uuid        NOT NULL DEFAULT uuidv7(),
    intake_id                uuid        NOT NULL,
    code                     text        NOT NULL,
    kind                     governance.requirement_kind   NOT NULL,
    statement                text        NOT NULL,
    acceptance_criteria      text,
    source                   text,
    status                   governance.requirement_status NOT NULL DEFAULT 'draft',
    parent_requirement_id    uuid,
    embedding                vector(384),
    embedding_model_id       uuid,
    embedding_input_hash     bytea,
    created_by               text        NOT NULL,
    acting_as_role           governance.studio_role,
    created_at               timestamptz NOT NULL DEFAULT now(),
    updated_at               timestamptz NOT NULL DEFAULT now(),
    CONSTRAINT pk_intake_requirement PRIMARY KEY (intake_requirement_id),
    CONSTRAINT fk_intake_requirement_intake
        FOREIGN KEY (intake_id)
        REFERENCES governance.intake (intake_id)
        ON DELETE CASCADE,
    CONSTRAINT fk_intake_requirement_parent
        FOREIGN KEY (parent_requirement_id)
        REFERENCES governance.intake_requirement (intake_requirement_id)
        ON DELETE SET NULL,
    CONSTRAINT fk_intake_requirement_embedding_config
        FOREIGN KEY (embedding_model_id)
        REFERENCES governance.embedding_config (embedding_config_id)
        ON DELETE SET NULL,
    CONSTRAINT uq_intake_requirement_intake_code UNIQUE (intake_id, code),
    CONSTRAINT ck_intake_requirement_not_self_parent
        CHECK (parent_requirement_id IS NULL OR parent_requirement_id <> intake_requirement_id)
);
COMMENT ON TABLE governance.intake_requirement IS 'tier:1 system-of-record. BR/FR/NFR/compliance requirements per intake; pgvector embedding for similarity.';
CREATE INDEX ix_intake_requirement_intake_id ON governance.intake_requirement (intake_id);
CREATE INDEX ix_intake_requirement_status    ON governance.intake_requirement (status);
CREATE INDEX ix_intake_requirement_parent_id ON governance.intake_requirement (parent_requirement_id);
-- pgvector cosine ANN index (ivfflat). Created conditionally at deploy if pgvector present.
CREATE INDEX ix_intake_requirement_embedding
    ON governance.intake_requirement USING ivfflat (embedding vector_cosine_ops) WITH (lists = 100);

-- ---------------------------------------------------------------------
-- TABLE: intake_entity_link  (Tier-1)  — v1, hardened
--   Bridge intake/requirement -> registry artifact (agent/task/prompt/tool ...).
--   v1 entity_id was a polymorphic app-validated FK; kept polymorphic (entity_type
--   spans agent/task/prompt/tool/test_suite/ground_truth_dataset, each its own table),
--   with the relationship captured via requirement_relationship enum.
-- ---------------------------------------------------------------------
CREATE TABLE governance.intake_entity_link (
    intake_entity_link_id  uuid        NOT NULL DEFAULT uuidv7(),
    intake_id              uuid        NOT NULL,
    requirement_id         uuid,
    entity_type            governance.entity_type NOT NULL,
    entity_id              uuid        NOT NULL,
    relationship           governance.requirement_relationship NOT NULL DEFAULT 'implements',
    created_by             text        NOT NULL,
    acting_as_role         governance.studio_role,
    created_at             timestamptz NOT NULL DEFAULT now(),
    CONSTRAINT pk_intake_entity_link PRIMARY KEY (intake_entity_link_id),
    CONSTRAINT fk_intake_entity_link_intake
        FOREIGN KEY (intake_id)
        REFERENCES governance.intake (intake_id)
        ON DELETE CASCADE,
    CONSTRAINT fk_intake_entity_link_requirement
        FOREIGN KEY (requirement_id)
        REFERENCES governance.intake_requirement (intake_requirement_id)
        ON DELETE SET NULL,
    CONSTRAINT uq_intake_entity_link
        UNIQUE (intake_id, requirement_id, entity_type, entity_id, relationship)
);
COMMENT ON TABLE governance.intake_entity_link IS 'tier:1 system-of-record. Bridge intake/requirement -> registry entity; entity_id is a polymorphic ref resolved per entity_type (no single DB FK; integrity enforced at API).';
CREATE INDEX ix_intake_entity_link_intake_id ON governance.intake_entity_link (intake_id);
CREATE INDEX ix_intake_entity_link_entity    ON governance.intake_entity_link (entity_type, entity_id);
-- Partial unique to forbid duplicate links when requirement_id is NULL (NULLs bypass the full uq).
CREATE UNIQUE INDEX uq_intake_entity_link_no_requirement
    ON governance.intake_entity_link (intake_id, entity_type, entity_id, relationship)
    WHERE requirement_id IS NULL;

-- ---------------------------------------------------------------------
-- TABLE: intake_artifact_plan  (Tier-1)  — v1, hardened
--   Proposed registry entities to build to satisfy the intake.
-- ---------------------------------------------------------------------
CREATE TABLE governance.intake_artifact_plan (
    intake_artifact_plan_id     uuid        NOT NULL DEFAULT uuidv7(),
    intake_id                   uuid        NOT NULL,
    requirement_id              uuid,
    proposed_kind               governance.entity_type        NOT NULL,
    proposed_name               text        NOT NULL,
    proposed_display_name       text        NOT NULL,
    proposed_description        text,
    proposed_purpose            text,
    proposed_inputs             jsonb       NOT NULL DEFAULT '{}'::jsonb,
    proposed_outputs            jsonb       NOT NULL DEFAULT '{}'::jsonb,
    proposed_capability_type    governance.capability_type,
    proposed_materiality_tier   governance.materiality_tier   NOT NULL,
    realized_entity_id          uuid,
    status                      governance.artifact_plan_status NOT NULL DEFAULT 'proposed',
    auto_generated              boolean     NOT NULL DEFAULT false,
    created_by                  text        NOT NULL,
    acting_as_role              governance.studio_role,
    created_at                  timestamptz NOT NULL DEFAULT now(),
    updated_at                  timestamptz NOT NULL DEFAULT now(),
    CONSTRAINT pk_intake_artifact_plan PRIMARY KEY (intake_artifact_plan_id),
    CONSTRAINT fk_intake_artifact_plan_intake
        FOREIGN KEY (intake_id)
        REFERENCES governance.intake (intake_id)
        ON DELETE CASCADE,
    CONSTRAINT fk_intake_artifact_plan_requirement
        FOREIGN KEY (requirement_id)
        REFERENCES governance.intake_requirement (intake_requirement_id)
        ON DELETE SET NULL,
    CONSTRAINT uq_intake_artifact_plan UNIQUE (intake_id, proposed_kind, proposed_name),
    CONSTRAINT ck_intake_artifact_plan_realized_when_realized
        CHECK (status <> 'realized' OR realized_entity_id IS NOT NULL),
    CONSTRAINT ck_intake_artifact_plan_inputs_object
        CHECK (jsonb_typeof(proposed_inputs) = 'object'),
    CONSTRAINT ck_intake_artifact_plan_outputs_object
        CHECK (jsonb_typeof(proposed_outputs) = 'object')
);
COMMENT ON TABLE governance.intake_artifact_plan IS 'tier:1 system-of-record. Planned registry entities for an intake; realized_entity_id is a polymorphic ref (no DB FK).';
CREATE INDEX ix_intake_artifact_plan_intake_id ON governance.intake_artifact_plan (intake_id);
CREATE INDEX ix_intake_artifact_plan_status    ON governance.intake_artifact_plan (status);

-- ---------------------------------------------------------------------
-- TABLE: intake_artifact_plan_estimate  (Tier-1)  — v1, hardened
--   Scenario-level cost forecast per plan row (Phase D).
-- ---------------------------------------------------------------------
CREATE TABLE governance.intake_artifact_plan_estimate (
    intake_artifact_plan_estimate_id    uuid        NOT NULL DEFAULT uuidv7(),
    intake_artifact_plan_id             uuid        NOT NULL,
    scenario_label                      text        NOT NULL DEFAULT 'expected',
    scenario_notes                      text,
    proposed_model_id                   uuid,
    purpose_text                        text,
    expected_input_size_tokens          integer,
    expected_output_size_tokens         integer,
    expected_invocations_per_year       integer,
    peak_multiplier                     numeric(6,2)  NOT NULL DEFAULT 1.00,
    seasonality_pattern_text            text,
    expected_tool_call_count            integer       NOT NULL DEFAULT 0,
    expected_input_file                 boolean       NOT NULL DEFAULT false,
    expected_input_file_avg_kb          integer,
    expected_input_file_max_kb          integer,
    cost_estimate_per_invocation_usd    numeric(14,6),
    cost_estimate_yearly_usd            numeric(14,2),
    estimate_basis                      jsonb,
    cost_override_yearly_usd            numeric(14,2),
    cost_override_explanation           text,
    is_active                           boolean       NOT NULL DEFAULT true,
    created_by                          text          NOT NULL,
    acting_as_role                      governance.studio_role,
    created_at                          timestamptz   NOT NULL DEFAULT now(),
    updated_at                          timestamptz   NOT NULL DEFAULT now(),
    CONSTRAINT pk_intake_artifact_plan_estimate PRIMARY KEY (intake_artifact_plan_estimate_id),
    CONSTRAINT fk_intake_artifact_plan_estimate_plan
        FOREIGN KEY (intake_artifact_plan_id)
        REFERENCES governance.intake_artifact_plan (intake_artifact_plan_id)
        ON DELETE CASCADE,
    CONSTRAINT fk_intake_artifact_plan_estimate_model
        FOREIGN KEY (proposed_model_id)
        REFERENCES governance.model (model_id)
        ON DELETE SET NULL,
    CONSTRAINT ck_intake_artifact_plan_estimate_override_pair
        CHECK ((cost_override_yearly_usd IS NULL) = (cost_override_explanation IS NULL)),
    CONSTRAINT ck_intake_artifact_plan_estimate_peak_positive
        CHECK (peak_multiplier > 0)
);
COMMENT ON TABLE governance.intake_artifact_plan_estimate IS 'tier:1 system-of-record. Scenario cost forecast per plan row; one active scenario per plan via partial unique.';
CREATE INDEX ix_intake_artifact_plan_estimate_plan_id
    ON governance.intake_artifact_plan_estimate (intake_artifact_plan_id);
CREATE UNIQUE INDEX uq_intake_artifact_plan_estimate_active
    ON governance.intake_artifact_plan_estimate (intake_artifact_plan_id)
    WHERE is_active = true;

-- ---------------------------------------------------------------------
-- TABLE: approval_request  (Tier-1)  — v1, hardened
--   One row per gating event. status promoted to enum.
-- ---------------------------------------------------------------------
CREATE TABLE governance.approval_request (
    approval_request_id   uuid        NOT NULL DEFAULT uuidv7(),
    intake_id             uuid        NOT NULL,
    kind                  governance.approval_request_kind   NOT NULL,
    target_entity_type    governance.entity_type,
    target_entity_id      uuid,
    required_roles        jsonb       NOT NULL,
    status                governance.approval_request_status NOT NULL DEFAULT 'pending',
    summary               text        NOT NULL,
    notes                 text,
    opened_at             timestamptz NOT NULL DEFAULT now(),
    opened_by             text        NOT NULL,
    opened_by_role        governance.studio_role,
    decided_at            timestamptz,
    created_at            timestamptz NOT NULL DEFAULT now(),
    updated_at            timestamptz NOT NULL DEFAULT now(),
    CONSTRAINT pk_approval_request PRIMARY KEY (approval_request_id),
    CONSTRAINT fk_approval_request_intake
        FOREIGN KEY (intake_id)
        REFERENCES governance.intake (intake_id)
        ON DELETE CASCADE,
    CONSTRAINT ck_approval_request_required_roles_array
        CHECK (jsonb_typeof(required_roles) = 'array'),
    CONSTRAINT ck_approval_request_decided_when_terminal
        CHECK (status = 'pending' OR decided_at IS NOT NULL),
    CONSTRAINT ck_approval_request_target_pair
        CHECK ((target_entity_type IS NULL) = (target_entity_id IS NULL))
);
COMMENT ON TABLE governance.approval_request IS 'tier:1 system-of-record. One gating event per row; target_entity_id polymorphic (no DB FK).';
CREATE INDEX ix_approval_request_intake_id ON governance.approval_request (intake_id);
CREATE INDEX ix_approval_request_status    ON governance.approval_request (status);

-- ---------------------------------------------------------------------
-- TABLE: approval_signoff  (Tier-1, APPEND-ONLY audit fact)  — v1, hardened
--   One row per approver per request. Insert-only: a sign-off is an immutable
--   decision fact (ADR-0005 rule 3). No updated_at; corrections are new rows.
-- ---------------------------------------------------------------------
CREATE TABLE governance.approval_signoff (
    approval_signoff_id   uuid        NOT NULL DEFAULT uuidv7(),
    approval_request_id   uuid        NOT NULL,
    role                  governance.approval_role     NOT NULL,
    approver_name         text        NOT NULL,
    approver_email        text,
    decision              governance.approval_decision NOT NULL,
    comment               text,
    evidence_url          text,
    signed_at             timestamptz NOT NULL DEFAULT now(),
    CONSTRAINT pk_approval_signoff PRIMARY KEY (approval_signoff_id),
    CONSTRAINT fk_approval_signoff_request
        FOREIGN KEY (approval_request_id)
        REFERENCES governance.approval_request (approval_request_id)
        ON DELETE CASCADE,
    CONSTRAINT uq_approval_signoff_request_role_email
        UNIQUE (approval_request_id, role, approver_email)
);
COMMENT ON TABLE governance.approval_signoff IS 'tier:1 append-only audit fact. Immutable per-approver sign-off; no in-place update — corrections are new rows.';
CREATE INDEX ix_approval_signoff_request_id ON governance.approval_signoff (approval_request_id);

-- ---------------------------------------------------------------------
-- TABLE: intake_roi_assessment  (Tier-1)  — v1, hardened
--   Intake-level business case / ROI (Phase D). One active scenario per intake.
-- ---------------------------------------------------------------------
CREATE TABLE governance.intake_roi_assessment (
    intake_roi_assessment_id          uuid        NOT NULL DEFAULT uuidv7(),
    intake_id                         uuid        NOT NULL,
    scenario_label                    text        NOT NULL DEFAULT 'expected',
    scenario_notes                    text,
    labor_hours_saved_per_year        numeric(12,2),
    loaded_labor_cost_per_hour_usd    numeric(10,2),
    annual_premium_in_scope_usd       numeric(14,2),
    loss_ratio_improvement_pp         numeric(6,3),
    submission_volume_per_year        integer,
    bind_rate_uplift_pp               numeric(6,3),
    avg_premium_per_bound_usd         numeric(12,2),
    risk_avoidance_yearly_usd         numeric(14,2),
    risk_avoidance_basis              text,
    other_benefit_label               text,
    other_benefit_yearly_usd          numeric(14,2),
    ai_spend_yearly_usd               numeric(14,2),
    ai_spend_basis                    text          NOT NULL DEFAULT 'cost_envelope',
    hitl_oversight_fte                numeric(6,2),
    hitl_loaded_cost_per_fte_usd      numeric(12,2),
    infrastructure_yearly_usd         numeric(12,2),
    build_cost_one_time_usd           numeric(14,2),
    horizon_years                     numeric(4,1)  NOT NULL DEFAULT 3.0,
    discount_rate_pct                 numeric(5,2)  NOT NULL DEFAULT 10.00,
    labor_savings_yearly_usd          numeric(14,2),
    loss_ratio_savings_yearly_usd     numeric(14,2),
    premium_uplift_yearly_usd         numeric(14,2),
    total_benefit_yearly_usd          numeric(14,2),
    total_run_cost_yearly_usd         numeric(14,2),
    net_annual_benefit_usd            numeric(14,2),
    payback_period_months             numeric(6,2),
    npv_horizon_usd                   numeric(14,2),
    roi_pct                           numeric(8,2),
    is_active                         boolean       NOT NULL DEFAULT true,
    locked_at                         timestamptz,
    locked_by                         text,
    locked_role                       governance.studio_role,
    approval_request_id               uuid,
    created_by                        text          NOT NULL,
    acting_as_role                    governance.studio_role,
    created_at                        timestamptz   NOT NULL DEFAULT now(),
    updated_at                        timestamptz   NOT NULL DEFAULT now(),
    CONSTRAINT pk_intake_roi_assessment PRIMARY KEY (intake_roi_assessment_id),
    CONSTRAINT fk_intake_roi_assessment_intake
        FOREIGN KEY (intake_id)
        REFERENCES governance.intake (intake_id)
        ON DELETE CASCADE,
    CONSTRAINT fk_intake_roi_assessment_approval_request
        FOREIGN KEY (approval_request_id)
        REFERENCES governance.approval_request (approval_request_id)
        ON DELETE SET NULL,
    CONSTRAINT ck_intake_roi_assessment_horizon_positive CHECK (horizon_years > 0),
    CONSTRAINT ck_intake_roi_assessment_locked_pair
        CHECK ((locked_at IS NULL) = (locked_by IS NULL))
);
COMMENT ON TABLE governance.intake_roi_assessment IS 'tier:1 system-of-record. Intake ROI/business case; one active scenario per intake via partial unique.';
CREATE INDEX ix_intake_roi_assessment_intake_id ON governance.intake_roi_assessment (intake_id);
CREATE UNIQUE INDEX uq_intake_roi_assessment_active
    ON governance.intake_roi_assessment (intake_id)
    WHERE is_active = true;

-- ---------------------------------------------------------------------
-- TABLE: intake_cost_envelope  (Tier-1)  — v1, hardened
--   Locked spend cap; one row per intake.
-- ---------------------------------------------------------------------
CREATE TABLE governance.intake_cost_envelope (
    intake_cost_envelope_id     uuid        NOT NULL DEFAULT uuidv7(),
    intake_id                   uuid        NOT NULL,
    total_yearly_estimate_usd   numeric(14,2) NOT NULL,
    upside_pct                  numeric(5,2)  NOT NULL DEFAULT 20.00,
    total_yearly_envelope_usd   numeric(14,2) NOT NULL,
    any_row_override            boolean       NOT NULL DEFAULT false,
    locked_at                   timestamptz   NOT NULL DEFAULT now(),
    locked_by                   text          NOT NULL,
    locked_role                 governance.studio_role NOT NULL,
    approval_request_id         uuid,
    notes                       text,
    created_at                  timestamptz   NOT NULL DEFAULT now(),
    updated_at                  timestamptz   NOT NULL DEFAULT now(),
    CONSTRAINT pk_intake_cost_envelope PRIMARY KEY (intake_cost_envelope_id),
    CONSTRAINT fk_intake_cost_envelope_intake
        FOREIGN KEY (intake_id)
        REFERENCES governance.intake (intake_id)
        ON DELETE CASCADE,
    CONSTRAINT fk_intake_cost_envelope_approval_request
        FOREIGN KEY (approval_request_id)
        REFERENCES governance.approval_request (approval_request_id)
        ON DELETE SET NULL,
    CONSTRAINT uq_intake_cost_envelope_intake UNIQUE (intake_id),
    CONSTRAINT ck_intake_cost_envelope_amounts_nonneg
        CHECK (total_yearly_estimate_usd >= 0 AND total_yearly_envelope_usd >= 0)
);
COMMENT ON TABLE governance.intake_cost_envelope IS 'tier:1 system-of-record. Locked spend cap, one per intake (uq on intake_id).';
CREATE INDEX ix_intake_cost_envelope_intake_id ON governance.intake_cost_envelope (intake_id);

-- =====================================================================
-- V2-NEW: OBLIGATION-SET LINKAGE (ADR-0008, FR-IN-014)
--   At intake + AI-risk classification the platform RESOLVES the applicable
--   canonical requirements (by governance domain + risk tier) and the target
--   maturity tiers — the "obligation set." Modeled as an append-only resolution
--   header + immutable obligation rows; the current obligation set is a VIEW
--   over the latest active resolution per intake (ADR-0005 rule 3 / ADR-0004).
--   Replaces v1's removed intake_canonical_link (which attached compliance to
--   capability, not intake — see mapping).
-- Cross-domain FKs (governance.canonical_requirement, governance.governance_domain,
--   governance.requirement_tier) are owned by the COMPLIANCE domain.
-- =====================================================================

-- Append-only resolution event: one row per (re)resolution of an intake's obligations.
CREATE TABLE governance.intake_obligation_resolution (
    intake_obligation_resolution_id  uuid        NOT NULL DEFAULT uuidv7(),
    intake_id                        uuid        NOT NULL,
    resolved_ai_risk_tier            governance.ai_risk_tier NOT NULL,
    resolved_naic_materiality        governance.naic_materiality NOT NULL,
    resolution_method                text        NOT NULL DEFAULT 'auto',
    resolver_notes                   text,
    superseded                       boolean     NOT NULL DEFAULT false,
    resolved_by                      text        NOT NULL,
    acting_as_role                   governance.studio_role,
    created_at                       timestamptz NOT NULL DEFAULT now(),
    CONSTRAINT pk_intake_obligation_resolution PRIMARY KEY (intake_obligation_resolution_id),
    CONSTRAINT fk_intake_obligation_resolution_intake
        FOREIGN KEY (intake_id)
        REFERENCES governance.intake (intake_id)
        ON DELETE CASCADE,
    CONSTRAINT ck_intake_obligation_resolution_method
        CHECK (resolution_method IN ('auto', 'manual', 'reclassification'))
);
COMMENT ON TABLE governance.intake_obligation_resolution IS 'tier:1 append-only. One obligation-set resolution per (re)classification of an intake; superseded flag marks history. FR-IN-014 / ADR-0008.';
CREATE INDEX ix_intake_obligation_resolution_intake_id
    ON governance.intake_obligation_resolution (intake_id, created_at DESC);
-- At most one active (non-superseded) resolution per intake.
CREATE UNIQUE INDEX uq_intake_obligation_resolution_active
    ON governance.intake_obligation_resolution (intake_id)
    WHERE superseded = false;

-- Immutable obligation rows: the resolved canonical requirements + target tier
-- (+ governance domain) that this intake must satisfy. Insert-only with the parent
-- resolution; a new resolution supersedes rather than mutating these rows.
CREATE TABLE governance.intake_obligation (
    intake_obligation_id             uuid        NOT NULL DEFAULT uuidv7(),
    intake_obligation_resolution_id  uuid        NOT NULL,
    intake_id                        uuid        NOT NULL,
    canonical_requirement_id         uuid        NOT NULL,
    governance_domain_id             uuid,
    target_requirement_tier_id       uuid,
    target_tier_level                integer     NOT NULL,
    is_mandatory                     boolean     NOT NULL DEFAULT true,
    rationale                        text,
    created_at                       timestamptz NOT NULL DEFAULT now(),
    CONSTRAINT pk_intake_obligation PRIMARY KEY (intake_obligation_id),
    CONSTRAINT fk_intake_obligation_resolution
        FOREIGN KEY (intake_obligation_resolution_id)
        REFERENCES governance.intake_obligation_resolution (intake_obligation_resolution_id)
        ON DELETE CASCADE,
    CONSTRAINT fk_intake_obligation_intake
        FOREIGN KEY (intake_id)
        REFERENCES governance.intake (intake_id)
        ON DELETE CASCADE,
    CONSTRAINT fk_intake_obligation_canonical_requirement
        FOREIGN KEY (canonical_requirement_id)
        REFERENCES governance.canonical_requirement (canonical_requirement_id)
        ON DELETE RESTRICT,
    CONSTRAINT fk_intake_obligation_governance_domain
        FOREIGN KEY (governance_domain_id)
        REFERENCES governance.governance_domain (governance_domain_id)
        ON DELETE RESTRICT,
    CONSTRAINT fk_intake_obligation_requirement_tier
        FOREIGN KEY (target_requirement_tier_id)
        REFERENCES governance.requirement_tier (requirement_tier_id)
        ON DELETE RESTRICT,
    CONSTRAINT uq_intake_obligation_resolution_requirement
        UNIQUE (intake_obligation_resolution_id, canonical_requirement_id),
    CONSTRAINT ck_intake_obligation_target_tier_positive
        CHECK (target_tier_level >= 1)
);
COMMENT ON TABLE governance.intake_obligation IS 'tier:1 append-only. Resolved obligation: a canonical_requirement + target maturity tier this intake must satisfy (cumulative). FR-IN-014 / ADR-0008.';
CREATE INDEX ix_intake_obligation_resolution_id
    ON governance.intake_obligation (intake_obligation_resolution_id);
CREATE INDEX ix_intake_obligation_intake_id
    ON governance.intake_obligation (intake_id);
CREATE INDEX ix_intake_obligation_canonical_requirement_id
    ON governance.intake_obligation (canonical_requirement_id);

-- Current obligation set per intake: obligations from the active resolution only.
CREATE VIEW governance.intake_obligation_current AS
SELECT o.intake_obligation_id,
       o.intake_id,
       r.intake_obligation_resolution_id,
       o.canonical_requirement_id,
       o.governance_domain_id,
       o.target_requirement_tier_id,
       o.target_tier_level,
       o.is_mandatory,
       o.rationale,
       r.resolved_ai_risk_tier,
       r.resolved_naic_materiality,
       r.created_at AS resolved_at
FROM   governance.intake_obligation AS o
JOIN   governance.intake_obligation_resolution AS r
       ON r.intake_obligation_resolution_id = o.intake_obligation_resolution_id
WHERE  r.superseded = false;
COMMENT ON VIEW governance.intake_obligation_current IS 'tier:1 projection. Live obligation set per intake = obligations under the non-superseded resolution. Generalizes the append-only/current-state pattern (ADR-0005 §7).';
