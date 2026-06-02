-- =====================================================================
-- 04-intake.sql — Verity v2 hardened schema · core INTAKE
-- Application onboarding, the intake/risk machine, requirements, the
-- impact assessment (KEEPS history), plan/estimate/ROI/cost (mutable figures),
-- the obligation -> compliance hand-off, and per-application app-team grants.
-- Re-applied per D4 (event/lock collapse; impact-assessment exception), D5, D6, D9.
-- =====================================================================

-- ===== application (the business app that owns intakes) ==============
CREATE TABLE core.application (
    application_id      uuid        NOT NULL DEFAULT uuidv7(),
    name                text        NOT NULL,
    description         text,
    created_at          timestamptz  NOT NULL DEFAULT now(),
    updated_at          timestamptz  NOT NULL DEFAULT now(),
    created_by_actor_id uuid        NOT NULL,
    created_role_code   text        NOT NULL,
    CONSTRAINT pk_application PRIMARY KEY (application_id),
    CONSTRAINT fk_application_created_by FOREIGN KEY (created_by_actor_id) REFERENCES core.actor (actor_id),
    CONSTRAINT fk_application_created_role FOREIGN KEY (created_role_code) REFERENCES reference.role (code),
    CONSTRAINT uq_application_name UNIQUE (name),
    CONSTRAINT ck_application_name_not_blank CHECK (length(btrim(name)) > 0));
COMMENT ON TABLE core.application IS 'tier:1. Business application that owns intakes/use-cases and (via app-team grants) its own team.';

-- wire deferred FKs from earlier domains now that core.application exists
ALTER TABLE core.automation_actor
    ADD CONSTRAINT fk_automation_actor_application
    FOREIGN KEY (application_id) REFERENCES core.application (application_id) ON DELETE RESTRICT;

-- ===== intake (header; status mutable per D4) =========================
CREATE TABLE core.intake (
    intake_id            uuid        NOT NULL DEFAULT uuidv7(),
    application_id       uuid        NOT NULL,
    title                text        NOT NULL,
    description          text,
    intake_status_code   text        NOT NULL DEFAULT 'proposed',   -- mutable (D4); history -> audit.status_transition
    ai_risk_tier_code    text,                                       -- classification (drives obligations)
    naic_materiality_code text,
    materiality_tier_code text,
    created_at           timestamptz  NOT NULL DEFAULT now(),
    updated_at           timestamptz  NOT NULL DEFAULT now(),
    created_by_actor_id  uuid        NOT NULL,
    created_role_code    text        NOT NULL,
    CONSTRAINT pk_intake PRIMARY KEY (intake_id),
    CONSTRAINT fk_intake_application FOREIGN KEY (application_id) REFERENCES core.application (application_id) ON DELETE RESTRICT,
    CONSTRAINT fk_intake_status FOREIGN KEY (intake_status_code) REFERENCES reference.intake_status (code),
    CONSTRAINT fk_intake_risk_tier FOREIGN KEY (ai_risk_tier_code) REFERENCES reference.ai_risk_tier (code),
    CONSTRAINT fk_intake_naic FOREIGN KEY (naic_materiality_code) REFERENCES reference.naic_materiality (code),
    CONSTRAINT fk_intake_materiality FOREIGN KEY (materiality_tier_code) REFERENCES reference.materiality_tier (code),
    CONSTRAINT fk_intake_created_by FOREIGN KEY (created_by_actor_id) REFERENCES core.actor (actor_id),
    CONSTRAINT fk_intake_created_role FOREIGN KEY (created_role_code) REFERENCES reference.role (code));
COMMENT ON TABLE core.intake IS 'tier:1. Use-case intake header. intake_status_code mutable (D4; transitions in audit.status_transition). Risk/materiality drive the obligation set.';
CREATE INDEX ix_intake_application ON core.intake (application_id);
CREATE INDEX ix_intake_status ON core.intake (intake_status_code);

-- now wire approval_request.target_intake_id (deferred from 03-lifecycle)
ALTER TABLE core.approval_request
    ADD CONSTRAINT fk_approval_request_target_intake
    FOREIGN KEY (target_intake_id) REFERENCES core.intake (intake_id) ON DELETE RESTRICT;

-- ===== intake_requirement (status mutable; embedding for similarity) ==
CREATE TABLE core.intake_requirement (
    intake_requirement_id uuid       NOT NULL DEFAULT uuidv7(),
    intake_id             uuid       NOT NULL,
    requirement_kind_code text       NOT NULL,
    requirement_status_code text     NOT NULL DEFAULT 'draft',     -- mutable (D4)
    title                 text       NOT NULL,
    body                  text       NOT NULL,
    embedding             vector(384),                              -- pgvector similarity (dim per embedding_config)
    created_at            timestamptz NOT NULL DEFAULT now(),
    updated_at            timestamptz NOT NULL DEFAULT now(),
    created_by_actor_id   uuid       NOT NULL,
    created_role_code     text       NOT NULL,
    CONSTRAINT pk_intake_requirement PRIMARY KEY (intake_requirement_id),
    CONSTRAINT fk_intake_requirement_intake FOREIGN KEY (intake_id) REFERENCES core.intake (intake_id) ON DELETE CASCADE,
    CONSTRAINT fk_intake_requirement_kind FOREIGN KEY (requirement_kind_code) REFERENCES reference.requirement_kind (code),
    CONSTRAINT fk_intake_requirement_status FOREIGN KEY (requirement_status_code) REFERENCES reference.requirement_status (code),
    CONSTRAINT fk_intake_requirement_created_by FOREIGN KEY (created_by_actor_id) REFERENCES core.actor (actor_id),
    CONSTRAINT fk_intake_requirement_created_role FOREIGN KEY (created_role_code) REFERENCES reference.role (code));
CREATE INDEX ix_intake_requirement_intake ON core.intake_requirement (intake_id);

-- ===== intake_impact_assessment (KEEPS HISTORY — SCD-2 versioned; D4 exception) =====
CREATE TABLE core.intake_impact_assessment (
    intake_impact_assessment_id uuid NOT NULL DEFAULT uuidv7(),
    intake_id            uuid       NOT NULL,
    revision             integer     NOT NULL,                      -- 1,2,3… immutable revisions
    assessment           jsonb       NOT NULL,                      -- the impact write-up (structured)
    valid_from           timestamptz NOT NULL DEFAULT now(),        -- SCD-2 window
    valid_to             timestamptz,                                -- NULL = current revision
    created_at           timestamptz NOT NULL DEFAULT now(),
    created_by_actor_id  uuid       NOT NULL,
    created_role_code    text       NOT NULL,
    CONSTRAINT pk_intake_impact_assessment PRIMARY KEY (intake_impact_assessment_id),
    CONSTRAINT fk_intake_impact_intake FOREIGN KEY (intake_id) REFERENCES core.intake (intake_id) ON DELETE CASCADE,
    CONSTRAINT fk_intake_impact_created_by FOREIGN KEY (created_by_actor_id) REFERENCES core.actor (actor_id),
    CONSTRAINT fk_intake_impact_created_role FOREIGN KEY (created_role_code) REFERENCES reference.role (code),
    CONSTRAINT uq_intake_impact_revision UNIQUE (intake_id, revision));
COMMENT ON TABLE core.intake_impact_assessment IS 'tier:1 SCD-2 versioned. The audit-sensitive figure that KEEPS full history (D4 exception): immutable revisions, current = valid_to IS NULL.';
CREATE VIEW core.intake_impact_assessment_current AS
SELECT * FROM core.intake_impact_assessment WHERE valid_to IS NULL;

-- ===== intake_artifact_plan (planned executable; status mutable) ======
CREATE TABLE core.intake_artifact_plan (
    intake_artifact_plan_id uuid     NOT NULL DEFAULT uuidv7(),
    intake_id              uuid      NOT NULL,
    planned_kind_code      text      NOT NULL,                       -- agent|task -> reference.executable_kind
    planned_name           text      NOT NULL,
    artifact_plan_status_code text   NOT NULL DEFAULT 'proposed',    -- mutable (D4)
    realized_executable_version_id uuid,                              -- D5: the built version (when realized)
    created_at             timestamptz NOT NULL DEFAULT now(),
    updated_at             timestamptz NOT NULL DEFAULT now(),
    created_by_actor_id    uuid      NOT NULL,
    created_role_code      text      NOT NULL,
    CONSTRAINT pk_intake_artifact_plan PRIMARY KEY (intake_artifact_plan_id),
    CONSTRAINT fk_intake_plan_intake FOREIGN KEY (intake_id) REFERENCES core.intake (intake_id) ON DELETE CASCADE,
    CONSTRAINT fk_intake_plan_kind FOREIGN KEY (planned_kind_code) REFERENCES reference.executable_kind (code),
    CONSTRAINT fk_intake_plan_status FOREIGN KEY (artifact_plan_status_code) REFERENCES reference.artifact_plan_status (code),
    CONSTRAINT fk_intake_plan_realized FOREIGN KEY (realized_executable_version_id) REFERENCES core.executable_version (executable_version_id) ON DELETE RESTRICT,
    CONSTRAINT fk_intake_plan_created_by FOREIGN KEY (created_by_actor_id) REFERENCES core.actor (actor_id),
    CONSTRAINT fk_intake_plan_created_role FOREIGN KEY (created_role_code) REFERENCES reference.role (code));
CREATE INDEX ix_intake_artifact_plan_intake ON core.intake_artifact_plan (intake_id);

-- ===== revisable figures (MUTABLE, no history per D4 — pivot to SCD if compliance requires) =====
CREATE TABLE core.intake_artifact_plan_estimate (
    intake_artifact_plan_estimate_id uuid NOT NULL DEFAULT uuidv7(),
    intake_artifact_plan_id uuid    NOT NULL,
    scenario               text     NOT NULL DEFAULT 'base',
    estimate               jsonb     NOT NULL,                       -- cost/effort forecast (mutable figure)
    model_id               uuid,                                      -- FK -> core.model in 06-decisions
    created_at             timestamptz NOT NULL DEFAULT now(),
    updated_at             timestamptz NOT NULL DEFAULT now(),
    updated_by_actor_id    uuid,
    updated_role_code      text,
    CONSTRAINT pk_intake_artifact_plan_estimate PRIMARY KEY (intake_artifact_plan_estimate_id),
    CONSTRAINT fk_intake_estimate_plan FOREIGN KEY (intake_artifact_plan_id) REFERENCES core.intake_artifact_plan (intake_artifact_plan_id) ON DELETE CASCADE,
    CONSTRAINT fk_intake_estimate_updated_by FOREIGN KEY (updated_by_actor_id) REFERENCES core.actor (actor_id),
    CONSTRAINT uq_intake_estimate_scenario UNIQUE (intake_artifact_plan_id, scenario));

CREATE TABLE core.intake_roi_assessment (
    intake_roi_assessment_id uuid    NOT NULL DEFAULT uuidv7(),
    intake_id              uuid      NOT NULL,
    scenario               text      NOT NULL DEFAULT 'base',
    roi                    jsonb      NOT NULL,                       -- ROI figures (mutable)
    locked                 boolean    NOT NULL DEFAULT false,         -- lock = mutable flag (was lock_event; transitions -> audit.status_transition)
    created_at             timestamptz NOT NULL DEFAULT now(),
    updated_at             timestamptz NOT NULL DEFAULT now(),
    updated_by_actor_id    uuid,
    updated_role_code      text,
    CONSTRAINT pk_intake_roi_assessment PRIMARY KEY (intake_roi_assessment_id),
    CONSTRAINT fk_intake_roi_intake FOREIGN KEY (intake_id) REFERENCES core.intake (intake_id) ON DELETE CASCADE,
    CONSTRAINT fk_intake_roi_updated_by FOREIGN KEY (updated_by_actor_id) REFERENCES core.actor (actor_id),
    CONSTRAINT uq_intake_roi_scenario UNIQUE (intake_id, scenario));

CREATE TABLE core.intake_cost_envelope (
    intake_cost_envelope_id uuid     NOT NULL DEFAULT uuidv7(),
    intake_id              uuid      NOT NULL,
    spend_cap              numeric(14,2) NOT NULL,
    currency_code          text      NOT NULL DEFAULT 'usd',         -- FK -> reference.currency (added in 06-decisions)
    locked                 boolean    NOT NULL DEFAULT false,
    created_at             timestamptz NOT NULL DEFAULT now(),
    updated_at             timestamptz NOT NULL DEFAULT now(),
    updated_by_actor_id    uuid,
    updated_role_code      text,
    CONSTRAINT pk_intake_cost_envelope PRIMARY KEY (intake_cost_envelope_id),
    CONSTRAINT fk_intake_cost_intake FOREIGN KEY (intake_id) REFERENCES core.intake (intake_id) ON DELETE CASCADE,
    CONSTRAINT fk_intake_cost_updated_by FOREIGN KEY (updated_by_actor_id) REFERENCES core.actor (actor_id),
    CONSTRAINT uq_intake_cost_envelope_intake UNIQUE (intake_id));   -- one per intake
COMMENT ON TABLE core.intake_cost_envelope IS 'tier:1 mutable. One spend cap per intake; locked is a mutable flag (lock/unlock transitions -> audit.status_transition). D4.';

-- ===== intake_entity_link (intake/requirement -> executable; D5) ======
CREATE TABLE core.intake_entity_link (
    intake_entity_link_id uuid       NOT NULL DEFAULT uuidv7(),
    intake_id             uuid       NOT NULL,
    intake_requirement_id uuid,                                       -- optional: link a specific requirement
    executable_id         uuid       NOT NULL,                        -- D5: a real FK, not polymorphic
    created_at            timestamptz NOT NULL DEFAULT now(),
    created_by_actor_id   uuid       NOT NULL,
    created_role_code     text       NOT NULL,
    CONSTRAINT pk_intake_entity_link PRIMARY KEY (intake_entity_link_id),
    CONSTRAINT fk_intake_entity_link_intake FOREIGN KEY (intake_id) REFERENCES core.intake (intake_id) ON DELETE CASCADE,
    CONSTRAINT fk_intake_entity_link_requirement FOREIGN KEY (intake_requirement_id) REFERENCES core.intake_requirement (intake_requirement_id) ON DELETE SET NULL,
    CONSTRAINT fk_intake_entity_link_executable FOREIGN KEY (executable_id) REFERENCES core.executable (executable_id) ON DELETE RESTRICT,
    CONSTRAINT fk_intake_entity_link_created_by FOREIGN KEY (created_by_actor_id) REFERENCES core.actor (actor_id),
    CONSTRAINT fk_intake_entity_link_created_role FOREIGN KEY (created_role_code) REFERENCES reference.role (code));

-- ===== OBLIGATION -> COMPLIANCE hand-off (FR-IN-014 / ADR-0008 / ADR-0009) =====
-- The resolution EVENT is append-only (auditors need "what was required as-of when").
-- Carries D9 provenance: how the obligation set was derived + ontology version + confidence.
CREATE TABLE core.intake_obligation_resolution (
    intake_obligation_resolution_id uuid NOT NULL DEFAULT uuidv7(),
    intake_id              uuid      NOT NULL,
    derivation_method_code text      NOT NULL DEFAULT 'manual',       -- manual|reasoner_recommended|human_validated (D9)
    ontology_version       text,                                      -- which axiom set produced it (D9; reproducibility)
    confidence             numeric(4,3),                              -- reasoner confidence (when applicable)
    resolved_by_actor_id   uuid      NOT NULL,
    resolved_role_code     text      NOT NULL,
    created_at             timestamptz NOT NULL DEFAULT now(),
    CONSTRAINT pk_intake_obligation_resolution PRIMARY KEY (intake_obligation_resolution_id),
    CONSTRAINT fk_intake_obl_res_intake FOREIGN KEY (intake_id) REFERENCES core.intake (intake_id) ON DELETE CASCADE,
    CONSTRAINT fk_intake_obl_res_method FOREIGN KEY (derivation_method_code) REFERENCES reference.derivation_method (code),
    CONSTRAINT fk_intake_obl_res_actor FOREIGN KEY (resolved_by_actor_id) REFERENCES core.actor (actor_id),
    CONSTRAINT fk_intake_obl_res_role FOREIGN KEY (resolved_role_code) REFERENCES reference.role (code));
COMMENT ON TABLE core.intake_obligation_resolution IS 'tier:1 append-only. One obligation-set resolution per (re)classification; latest = current, history retained. D9 provenance (method/ontology_version/confidence).';
CREATE INDEX ix_intake_obl_res_intake_time ON core.intake_obligation_resolution (intake_id, created_at DESC);

-- the resolved obligations: canonical requirement + target tier (+ domain). FKs to compliance deferred to 05.
CREATE TABLE core.intake_obligation (
    intake_obligation_id   uuid      NOT NULL DEFAULT uuidv7(),
    intake_obligation_resolution_id uuid NOT NULL,
    canonical_requirement_id uuid    NOT NULL,                        -- FK -> compliance.canonical_requirement (05)
    governance_domain_code text,                                      -- FK -> reference/compliance domain (05)
    target_requirement_tier_id uuid,                                  -- FK -> compliance.requirement_tier (05)
    created_at             timestamptz NOT NULL DEFAULT now(),
    CONSTRAINT pk_intake_obligation PRIMARY KEY (intake_obligation_id),
    CONSTRAINT fk_intake_obligation_resolution FOREIGN KEY (intake_obligation_resolution_id)
        REFERENCES core.intake_obligation_resolution (intake_obligation_resolution_id) ON DELETE CASCADE);
COMMENT ON TABLE core.intake_obligation IS 'tier:1. A resolved obligation (canonical_requirement + target tier) this intake must satisfy. Compliance FKs wired in 05-compliance (deferred). FR-IN-014.';

-- ===== app-team grants (per-application roles; D6) ====================
CREATE TABLE core.actor_app_role_grant (
    actor_app_role_grant_id uuid     NOT NULL DEFAULT uuidv7(),
    actor_id               uuid      NOT NULL,
    application_id         uuid      NOT NULL,
    app_team_role_code     text      NOT NULL,
    is_revocation          boolean    NOT NULL DEFAULT false,
    granted_by_actor_id    uuid      NOT NULL,
    acting_role_code       text      NOT NULL,
    reason                 text,
    created_at             timestamptz NOT NULL DEFAULT now(),
    CONSTRAINT pk_actor_app_role_grant PRIMARY KEY (actor_app_role_grant_id),
    CONSTRAINT fk_actor_app_grant_actor FOREIGN KEY (actor_id) REFERENCES core.actor (actor_id) ON DELETE RESTRICT,
    CONSTRAINT fk_actor_app_grant_application FOREIGN KEY (application_id) REFERENCES core.application (application_id) ON DELETE RESTRICT,
    CONSTRAINT fk_actor_app_grant_role FOREIGN KEY (app_team_role_code) REFERENCES reference.app_team_role (code),
    CONSTRAINT fk_actor_app_grant_granted_by FOREIGN KEY (granted_by_actor_id) REFERENCES core.actor (actor_id),
    CONSTRAINT fk_actor_app_grant_acting_role FOREIGN KEY (acting_role_code) REFERENCES reference.role (code));
COMMENT ON TABLE core.actor_app_role_grant IS 'tier:1 append-only. Per-application app-team role grants (app_demo_*). Current via current_actor_app_role. D6.';
CREATE INDEX ix_actor_app_grant_actor_app_role_time
    ON core.actor_app_role_grant (actor_id, application_id, app_team_role_code, created_at DESC);

CREATE VIEW core.current_actor_app_role AS
SELECT actor_id, application_id, app_team_role_code
FROM (
    SELECT DISTINCT ON (actor_id, application_id, app_team_role_code)
           actor_id, application_id, app_team_role_code, is_revocation
    FROM   core.actor_app_role_grant
    ORDER  BY actor_id, application_id, app_team_role_code, created_at DESC
) latest
WHERE NOT is_revocation;
COMMENT ON VIEW core.current_actor_app_role IS 'Effective per-application app-team roles per actor (latest non-revoked grant). D6.';
