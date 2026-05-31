-- 03-lifecycle_approvals.sql — hardened v2 schema domain: lifecycle_approvals
-- See ASSEMBLY-AND-VERIFICATION.md for cross-domain FKs & review items.

-- =====================================================================
-- DOMAIN: LIFECYCLE, PROMOTION & APPROVALS  (v2 hardened, ADR-0005)
-- Schema: governance.  Conventions per specs/schema/naming-conventions.md.
-- Surrogate PKs uuidv7() (PG18+; fallback note below). Append-only event
-- tables + current-state VIEWS generalize v1's event-sourced run model.
-- =====================================================================
-- PORTABILITY: uuidv7() requires PostgreSQL 18+. On <18, create a fallback:
--   CREATE FUNCTION governance.uuidv7() RETURNS uuid LANGUAGE sql VOLATILE
--   AS $$ SELECT gen_random_uuid() $$;  -- swap for a true v7 impl in prod.
-- This DDL calls uuidv7() unqualified; deploy the fallback in search_path.

-- ---------------------------------------------------------------------
-- ENUMS (verbatim controlled vocabularies)
-- ---------------------------------------------------------------------

-- 7-state lifecycle, verbatim from v1 governance.lifecycle_state.
CREATE TYPE governance.lifecycle_state AS ENUM (
    'draft', 'candidate', 'staging', 'shadow', 'challenger', 'champion', 'deprecated'
);
COMMENT ON TYPE governance.lifecycle_state IS
    'tier:1 — 7-state lifecycle, verbatim from v1.';

-- Deployment channel/environment-mode, verbatim from v1 deployment_channel.
CREATE TYPE governance.deployment_channel AS ENUM (
    'development', 'staging', 'shadow', 'evaluation', 'production'
);

-- Entity kinds that have a lifecycle/version (agent, task, prompt).
-- Mirrors v1 governance.entity_type membership relevant to this domain.
CREATE TYPE governance.versioned_entity_type AS ENUM ('agent', 'task', 'prompt');
COMMENT ON TYPE governance.versioned_entity_type IS
    'tier:1 — entity kinds that own a version row + lifecycle. Subset of v1 entity_type.';

-- Approval-request kind, verbatim from v1 governance.approval_request_kind.
CREATE TYPE governance.approval_request_kind AS ENUM (
    'intake', 'risk_reclassification', 'promote_candidate', 'promote_champion', 'retire'
);

-- Approval-request status (v1 stored a free varchar(20) 'pending'; hardened to an enum).
CREATE TYPE governance.approval_request_status AS ENUM (
    'pending', 'approved', 'rejected', 'withdrawn'
);
COMMENT ON TYPE governance.approval_request_status IS
    'tier:1 — replaces v1 approval_request.status free varchar(20).';

-- Per-approver decision, verbatim from v1 governance.approval_decision.
CREATE TYPE governance.approval_decision AS ENUM (
    'approved', 'rejected', 'requested_changes', 'abstained'
);

-- The 7 governance personas permitted to sign off (approval subset of platform_role).
-- Verbatim from v1 governance.approval_role. (engineer/auditor/viewer excluded.)
CREATE TYPE governance.approval_role AS ENUM (
    'business_owner', 'compliance', 'legal', 'model_risk', 'ai_governance', 'security', 'privacy'
);

-- AI risk tier (drives required-role sets), verbatim from v1 governance.ai_risk_tier.
CREATE TYPE governance.ai_risk_tier AS ENUM ('minimal', 'limited', 'high', 'unacceptable');

-- Materiality tier, verbatim from v1 governance.materiality_tier.
CREATE TYPE governance.materiality_tier AS ENUM ('high', 'medium', 'low');

-- Package kind for promotion artifacts (.vtx task / .vax agent), ADR-0006 / PCR 3.2.
CREATE TYPE governance.package_kind AS ENUM ('vtx', 'vax');
COMMENT ON TYPE governance.package_kind IS 'tier:1 — .vtx=task package, .vax=agent package.';

-- Deployment operation, verbatim from ADR-0006 action vocabulary.
CREATE TYPE governance.deployment_action AS ENUM (
    'deploy_nonprod', 'deploy_prod', 'promote_champion', 'lock_deprecated', 'cleanup_deprecated'
);

-- Deployment run-mode, encoding ADR-0006 state->run-mode matrix.
CREATE TYPE governance.deployment_run_mode AS ENUM ('live', 'read_only', 'ab', 'locked');

-- Environment class for clusters (ADR-0006: non-prod vs prod, plus ephemeral replay).
CREATE TYPE governance.environment_class AS ENUM ('non_prod', 'prod', 'ephemeral');

-- Outcome of an append-only deployment attempt.
CREATE TYPE governance.deployment_outcome AS ENUM ('succeeded', 'rejected', 'failed');

-- Run-dispatch outbox publish state (PCR 3.3 transactional outbox).
CREATE TYPE governance.outbox_status AS ENUM ('pending', 'published', 'claimed', 'dead_letter');

-- ---------------------------------------------------------------------
-- 1. LIFECYCLE STATE MACHINE  (append-only; generalizes v1 mutable column)
--    v1 stored lifecycle_state as a mutable column on agent_version /
--    task_version / prompt_version. v2 makes the transition the fact.
-- ---------------------------------------------------------------------
CREATE TABLE governance.lifecycle_event (
    lifecycle_event_id  uuid                         NOT NULL DEFAULT uuidv7(),
    entity_type         governance.versioned_entity_type NOT NULL,
    entity_version_id   uuid                         NOT NULL,  -- agent_version/task_version/prompt_version PK (polymorphic; app-validated)
    from_state          governance.lifecycle_state,             -- NULL on initial 'draft' creation
    to_state            governance.lifecycle_state   NOT NULL,
    channel             governance.deployment_channel,
    approval_request_id uuid,                                   -- gating approval that authorized this transition (nullable)
    actor_user_id       uuid                         NOT NULL,  -- server-resolved principal (auth.user)
    rationale           text                         NOT NULL,
    detail              jsonb       NOT NULL DEFAULT '{}'::jsonb,
    created_at          timestamptz NOT NULL DEFAULT now(),
    CONSTRAINT pk_lifecycle_event PRIMARY KEY (lifecycle_event_id),
    CONSTRAINT fk_lifecycle_event_approval_request
        FOREIGN KEY (approval_request_id)
        REFERENCES governance.approval_request (approval_request_id) ON DELETE RESTRICT,
    CONSTRAINT ck_lifecycle_event_no_self_loop
        CHECK (from_state IS NULL OR from_state <> to_state)
);
COMMENT ON TABLE governance.lifecycle_event IS
    'tier:1 append-only — one row per lifecycle state transition per entity version. Current state is governance.entity_lifecycle_current.';
CREATE INDEX ix_lifecycle_event_entity
    ON governance.lifecycle_event (entity_type, entity_version_id, created_at DESC);
CREATE INDEX ix_lifecycle_event_to_state
    ON governance.lifecycle_event (to_state);
CREATE INDEX ix_lifecycle_event_approval_request_id
    ON governance.lifecycle_event (approval_request_id);

-- Current lifecycle state = latest event per entity version.
CREATE VIEW governance.entity_lifecycle_current AS
SELECT DISTINCT ON (e.entity_type, e.entity_version_id)
       e.entity_type,
       e.entity_version_id,
       e.to_state          AS lifecycle_state,
       e.channel,
       e.actor_user_id     AS last_actor_user_id,
       e.created_at        AS state_since
FROM   governance.lifecycle_event AS e
ORDER  BY e.entity_type, e.entity_version_id, e.created_at DESC;
COMMENT ON VIEW governance.entity_lifecycle_current IS
    'tier:1 projection — latest lifecycle_event per (entity_type, entity_version_id).';

-- ---------------------------------------------------------------------
-- 2. CHAMPION RESOLUTION  (append-only; replaces v1 no-FK soft pointers)
--    v1: agent.current_champion_version_id / task.current_champion_version_id
--    were nullable UUIDs with NO FK, mutated in place. v2: the champion is the
--    latest non-retired champion_assignment per (entity_type, entity_id).
-- ---------------------------------------------------------------------
CREATE TABLE governance.champion_assignment (
    champion_assignment_id uuid                         NOT NULL DEFAULT uuidv7(),
    entity_type            governance.versioned_entity_type NOT NULL,
    entity_id              uuid                         NOT NULL,  -- the registry entity (agent/task/prompt), app-validated polymorphic
    entity_version_id      uuid                         NOT NULL,  -- the version becoming/leaving champion
    is_retirement          boolean     NOT NULL DEFAULT false,     -- true = this entity has no champion as of this event
    promotion_id           uuid,                                   -- the promotion that minted the package, when applicable
    actor_user_id          uuid        NOT NULL,                   -- server-resolved principal
    rationale              text        NOT NULL,
    champion_since         timestamptz NOT NULL DEFAULT now(),
    created_at             timestamptz NOT NULL DEFAULT now(),
    CONSTRAINT pk_champion_assignment PRIMARY KEY (champion_assignment_id),
    CONSTRAINT fk_champion_assignment_promotion
        FOREIGN KEY (promotion_id)
        REFERENCES governance.promotion (promotion_id) ON DELETE RESTRICT,
    CONSTRAINT ck_champion_assignment_retirement_no_promotion
        CHECK (NOT is_retirement OR promotion_id IS NULL)
);
COMMENT ON TABLE governance.champion_assignment IS
    'tier:1 append-only — replaces v1 agent.current_champion_version_id / task.current_champion_version_id (no-FK mutable). Current champion = governance.entity_champion_current.';
CREATE INDEX ix_champion_assignment_entity
    ON governance.champion_assignment (entity_type, entity_id, created_at DESC);
CREATE INDEX ix_champion_assignment_promotion_id
    ON governance.champion_assignment (promotion_id);

-- Current champion = latest assignment per entity, excluding retirements.
CREATE VIEW governance.entity_champion_current AS
SELECT entity_type, entity_id, entity_version_id, promotion_id, champion_since
FROM (
    SELECT DISTINCT ON (a.entity_type, a.entity_id)
           a.entity_type, a.entity_id, a.entity_version_id,
           a.promotion_id, a.champion_since, a.is_retirement
    FROM   governance.champion_assignment AS a
    ORDER  BY a.entity_type, a.entity_id, a.created_at DESC
) latest
WHERE latest.is_retirement = false;
COMMENT ON VIEW governance.entity_champion_current IS
    'tier:1 projection — latest non-retirement champion_assignment per (entity_type, entity_id).';

-- ---------------------------------------------------------------------
-- 3. APPROVAL REQUEST / SIGNOFF  (hardened from intake inventory)
--    v1: approval_request.status was free varchar(20); required_roles jsonb;
--    target_entity_id polymorphic no-FK; approval_signoff keyed on email.
-- ---------------------------------------------------------------------
CREATE TABLE governance.approval_request (
    approval_request_id uuid                              NOT NULL DEFAULT uuidv7(),
    intake_id           uuid                              NOT NULL,
    kind                governance.approval_request_kind  NOT NULL,
    target_entity_type  governance.versioned_entity_type,           -- nullable (intake-level requests have no target version)
    target_entity_id    uuid,                                        -- polymorphic registry ref; app-validated (no DB FK by design)
    ai_risk_tier        governance.ai_risk_tier           NOT NULL,  -- drives required-role set (v1 REQUIRED_ROLES_BY_RISK_TIER)
    status              governance.approval_request_status NOT NULL DEFAULT 'pending',
    summary             text                              NOT NULL,
    notes               text,
    opened_by_user_id   uuid                              NOT NULL,  -- server-resolved (FR-018); replaces v1 opened_by/opened_by_role
    opened_at           timestamptz                       NOT NULL DEFAULT now(),
    decided_at          timestamptz,
    CONSTRAINT pk_approval_request PRIMARY KEY (approval_request_id),
    CONSTRAINT fk_approval_request_intake
        FOREIGN KEY (intake_id)
        REFERENCES governance.intake (intake_id) ON DELETE CASCADE,
    CONSTRAINT ck_approval_request_decided_when_resolved
        CHECK ((status = 'pending') = (decided_at IS NULL)),
    CONSTRAINT ck_approval_request_target_pair
        CHECK ((target_entity_type IS NULL) = (target_entity_id IS NULL))
);
COMMENT ON TABLE governance.approval_request IS
    'tier:1 — one row per gating event. Hardened from v1: status now enum, ai_risk_tier captured, opener bound to user_id (FR-018). required_roles jsonb dropped: derived from ai_risk_tier per the v1 risk-tier matrix.';
CREATE INDEX ix_approval_request_intake_id ON governance.approval_request (intake_id);
CREATE INDEX ix_approval_request_status     ON governance.approval_request (status);
CREATE INDEX ix_approval_request_target
    ON governance.approval_request (target_entity_type, target_entity_id);

-- One immutable signoff per approver per request. Append-only audit fact.
CREATE TABLE governance.approval_signoff (
    approval_signoff_id uuid                        NOT NULL DEFAULT uuidv7(),
    approval_request_id uuid                        NOT NULL,
    role                governance.approval_role    NOT NULL,        -- the 7-role subset only (segregation of duties)
    approver_user_id    uuid                        NOT NULL,        -- server-resolved principal (FR-018); replaces v1 email key
    decision            governance.approval_decision NOT NULL,
    comment             text,
    evidence_url        text,
    signed_at           timestamptz                 NOT NULL DEFAULT now(),
    CONSTRAINT pk_approval_signoff PRIMARY KEY (approval_signoff_id),
    CONSTRAINT fk_approval_signoff_request
        FOREIGN KEY (approval_request_id)
        REFERENCES governance.approval_request (approval_request_id) ON DELETE CASCADE,
    CONSTRAINT uq_approval_signoff_request_role_user
        UNIQUE (approval_request_id, role, approver_user_id)
);
COMMENT ON TABLE governance.approval_signoff IS
    'tier:1 append-only — one signoff per (request, role, approver). v1 keyed on approver_email; v2 keys on approver_user_id (FR-018).';
CREATE INDEX ix_approval_signoff_approval_request_id
    ON governance.approval_signoff (approval_request_id);

-- ---------------------------------------------------------------------
-- 4. PROMOTION ATTESTATION  (the champion package, PCR 3.2 + ADR-0006)
--    Replaces v1 governance.approval_record (the lifecycle gate / champion-
--    confirmation record). The promotion event captures the .vtx/.vax package
--    digest, the config snapshot, the gate-review attestation flags, and the
--    deploy-time compatible harness image (digest-pinned).
-- ---------------------------------------------------------------------
CREATE TABLE governance.promotion (
    promotion_id          uuid                              NOT NULL DEFAULT uuidv7(),
    entity_type           governance.versioned_entity_type  NOT NULL,
    entity_version_id     uuid                              NOT NULL,
    approval_request_id   uuid                              NOT NULL,   -- the promote_champion request that authorized this
    package_id            uuid                              NOT NULL,   -- the .vtx/.vax produced at promotion
    from_state            governance.lifecycle_state        NOT NULL,
    to_state              governance.lifecycle_state        NOT NULL,
    materiality_tier      governance.materiality_tier       NOT NULL,
    inference_config_snapshot jsonb                         NOT NULL,   -- config.json snapshot at promotion (PCR 3.2)
    promoted_by_user_id   uuid                              NOT NULL,   -- server-resolved (replaces v1 approver_name)
    rationale             text                              NOT NULL,   -- replaces v1 approval_record.rationale (NOT NULL)
    -- Gate-review attestation flags (verbatim from v1 approval_record).
    staging_results_reviewed    boolean NOT NULL DEFAULT false,
    ground_truth_reviewed       boolean NOT NULL DEFAULT false,
    fairness_analysis_reviewed  boolean NOT NULL DEFAULT false,
    shadow_metrics_reviewed     boolean NOT NULL DEFAULT false,
    challenger_metrics_reviewed boolean NOT NULL DEFAULT false,
    model_card_reviewed         boolean NOT NULL DEFAULT false,
    similarity_flags_reviewed   boolean NOT NULL DEFAULT false,
    champion_confirmation_satisfied boolean NOT NULL DEFAULT false,
    decision_override           boolean NOT NULL DEFAULT false,
    override_reason             text,
    promoted_at           timestamptz NOT NULL DEFAULT now(),
    CONSTRAINT pk_promotion PRIMARY KEY (promotion_id),
    CONSTRAINT fk_promotion_approval_request
        FOREIGN KEY (approval_request_id)
        REFERENCES governance.approval_request (approval_request_id) ON DELETE RESTRICT,
    CONSTRAINT fk_promotion_package
        FOREIGN KEY (package_id)
        REFERENCES governance.package (package_id) ON DELETE RESTRICT,
    CONSTRAINT ck_promotion_override_reason
        CHECK (NOT decision_override OR override_reason IS NOT NULL),
    CONSTRAINT ck_promotion_state_advance
        CHECK (from_state <> to_state)
);
COMMENT ON TABLE governance.promotion IS
    'tier:1 append-only — promotion/attestation event. Replaces v1 governance.approval_record (lifecycle gate + champion_confirmation_satisfied); binds the .vtx/.vax package and config snapshot at the moment of champion promotion (PCR 3.2).';
CREATE INDEX ix_promotion_entity
    ON governance.promotion (entity_type, entity_version_id, promoted_at DESC);
CREATE INDEX ix_promotion_approval_request_id ON governance.promotion (approval_request_id);
CREATE INDEX ix_promotion_package_id          ON governance.promotion (package_id);

-- ---------------------------------------------------------------------
-- 5. PACKAGE & HARNESS IMAGE REGISTRY  (V2-NEW, ADR-0006 / PCR 3.2)
-- ---------------------------------------------------------------------
CREATE TABLE governance.harness_image (
    harness_image_id uuid        NOT NULL DEFAULT uuidv7(),
    image_repository text        NOT NULL,                  -- e.g. registry/verity-runtime
    image_digest     text        NOT NULL,                  -- immutable content digest (sha256:...); NOT a tag (ADR-0006)
    display_name     text        NOT NULL,
    description      text,
    is_active        boolean     NOT NULL DEFAULT true,
    created_at       timestamptz NOT NULL DEFAULT now(),
    CONSTRAINT pk_harness_image PRIMARY KEY (harness_image_id),
    CONSTRAINT uq_harness_image_digest UNIQUE (image_digest),
    CONSTRAINT ck_harness_image_digest_sha256
        CHECK (image_digest LIKE 'sha256:%')
);
COMMENT ON TABLE governance.harness_image IS
    'tier:1 — registry of executable harness images, identified by immutable content digest (ADR-0006; tag-based compatibility prohibited).';

CREATE TABLE governance.package (
    package_id        uuid                             NOT NULL DEFAULT uuidv7(),
    entity_type       governance.versioned_entity_type NOT NULL,
    entity_version_id uuid                             NOT NULL,
    package_kind      governance.package_kind          NOT NULL,   -- vtx (task) / vax (agent)
    manifest_digest   text                             NOT NULL,   -- SHA-256 of manifest.json (integrity anchor, PCR 3.2)
    storage_uri       text                             NOT NULL,   -- object-store address (MinIO) of the bundle
    built_by_user_id  uuid                             NOT NULL,
    created_at        timestamptz NOT NULL DEFAULT now(),
    CONSTRAINT pk_package PRIMARY KEY (package_id),
    CONSTRAINT uq_package_manifest_digest UNIQUE (manifest_digest),
    CONSTRAINT ck_package_manifest_sha256
        CHECK (manifest_digest LIKE 'sha256:%'),
    CONSTRAINT ck_package_kind_matches_entity
        CHECK ( (package_kind = 'vtx' AND entity_type = 'task')
             OR (package_kind = 'vax' AND entity_type = 'agent') )
);
COMMENT ON TABLE governance.package IS
    'tier:1 append-only — .vtx/.vax deployment artifact built at champion promotion (PCR 3.2); manifest_digest is the SHA-256 integrity anchor.';
CREATE INDEX ix_package_entity
    ON governance.package (entity_type, entity_version_id);

-- Many-to-many digest-pinned compatibility: which images can execute a package (ADR-0006 §2).
CREATE TABLE governance.package_image_compatibility (
    package_image_compatibility_id uuid NOT NULL DEFAULT uuidv7(),
    package_id       uuid        NOT NULL,
    harness_image_id uuid        NOT NULL,
    created_at       timestamptz NOT NULL DEFAULT now(),
    CONSTRAINT pk_package_image_compatibility PRIMARY KEY (package_image_compatibility_id),
    CONSTRAINT fk_package_image_compatibility_package
        FOREIGN KEY (package_id)
        REFERENCES governance.package (package_id) ON DELETE CASCADE,
    CONSTRAINT fk_package_image_compatibility_image
        FOREIGN KEY (harness_image_id)
        REFERENCES governance.harness_image (harness_image_id) ON DELETE RESTRICT,
    CONSTRAINT uq_package_image_compatibility UNIQUE (package_id, harness_image_id)
);
COMMENT ON TABLE governance.package_image_compatibility IS
    'tier:1 — declared package x harness-image compatibility (digest-pinned). The deploy gate refuses any combination absent here (ADR-0006 §2).';
CREATE INDEX ix_package_image_compatibility_image_id
    ON governance.package_image_compatibility (harness_image_id);

-- Cluster registry: where packages may run (ADR-0006 §1).
CREATE TABLE governance.cluster (
    cluster_id        uuid                          NOT NULL DEFAULT uuidv7(),
    name              text                          NOT NULL,
    environment_class governance.environment_class  NOT NULL,
    description       text,
    is_active         boolean     NOT NULL DEFAULT true,
    created_at        timestamptz NOT NULL DEFAULT now(),
    CONSTRAINT pk_cluster PRIMARY KEY (cluster_id),
    CONSTRAINT uq_cluster_name UNIQUE (name)
);
COMMENT ON TABLE governance.cluster IS
    'tier:1 — clusters grouped into environments (non_prod/prod/ephemeral) for placement gating (ADR-0006).';

-- ---------------------------------------------------------------------
-- 6. DEPLOYMENT INVENTORY  (V2-NEW, ADR-0006 §3, append-only, Tier-1)
--    actor / target / outcome; lifecycle-gated placement.
-- ---------------------------------------------------------------------
CREATE TABLE governance.deployment_event (
    deployment_event_id uuid                           NOT NULL DEFAULT uuidv7(),
    package_id          uuid                           NOT NULL,
    harness_image_id    uuid                           NOT NULL,   -- the digest-pinned image deployed onto
    cluster_id          uuid                           NOT NULL,
    action              governance.deployment_action   NOT NULL,
    lifecycle_state     governance.lifecycle_state     NOT NULL,   -- state of the package's version at deploy time (gates placement)
    run_mode            governance.deployment_run_mode NOT NULL,   -- live/read_only/ab/locked per ADR-0006 matrix
    outcome             governance.deployment_outcome  NOT NULL,
    rejection_reason    text,                                       -- required when outcome='rejected'
    actor_user_id       uuid                           NOT NULL,
    created_at          timestamptz NOT NULL DEFAULT now(),
    CONSTRAINT pk_deployment_event PRIMARY KEY (deployment_event_id),
    CONSTRAINT fk_deployment_event_package
        FOREIGN KEY (package_id)
        REFERENCES governance.package (package_id) ON DELETE RESTRICT,
    CONSTRAINT fk_deployment_event_image
        FOREIGN KEY (harness_image_id)
        REFERENCES governance.harness_image (harness_image_id) ON DELETE RESTRICT,
    CONSTRAINT fk_deployment_event_cluster
        FOREIGN KEY (cluster_id)
        REFERENCES governance.cluster (cluster_id) ON DELETE RESTRICT,
    CONSTRAINT ck_deployment_event_rejection_reason
        CHECK (outcome <> 'rejected' OR rejection_reason IS NOT NULL),
    -- ADR-0006 state->environment matrix (hard rule, not convention).
    CONSTRAINT ck_deployment_event_state_environment
        CHECK (outcome <> 'succeeded' OR lifecycle_state IN
               ('staging','shadow','challenger','champion','deprecated')),
    -- ADR-0006 read-only states must not deploy in 'live' mode.
    CONSTRAINT ck_deployment_event_readonly_states
        CHECK (lifecycle_state NOT IN ('shadow') OR run_mode IN ('read_only'))
);
COMMENT ON TABLE governance.deployment_event IS
    'tier:1 append-only — deployment inventory (ADR-0006 §3): what package, on which image digest, in which cluster, at which lifecycle state/run-mode, by whom, with what outcome. Out-of-band deploys are disallowed. Current placement = governance.deployment_current.';
CREATE INDEX ix_deployment_event_package_id  ON governance.deployment_event (package_id, created_at DESC);
CREATE INDEX ix_deployment_event_cluster_id  ON governance.deployment_event (cluster_id, created_at DESC);
CREATE INDEX ix_deployment_event_image_id    ON governance.deployment_event (harness_image_id);

-- Current placement = latest succeeded deployment per (package, cluster) not subsequently locked/cleaned.
CREATE VIEW governance.deployment_current AS
SELECT DISTINCT ON (d.package_id, d.cluster_id)
       d.package_id, d.cluster_id, d.harness_image_id,
       d.lifecycle_state, d.run_mode, d.action, d.created_at AS deployed_at
FROM   governance.deployment_event AS d
WHERE  d.outcome = 'succeeded'
ORDER  BY d.package_id, d.cluster_id, d.created_at DESC;
COMMENT ON VIEW governance.deployment_current IS
    'tier:1 projection — latest succeeded deployment_event per (package, cluster).';

-- ---------------------------------------------------------------------
-- 7. PLAN / ENVELOPE / ROI LOCKS  (hardened from intake inventory)
--    locked_by attribution bound to user_id (FR-018); lock invariants encoded.
-- ---------------------------------------------------------------------
CREATE TABLE governance.intake_artifact_plan_estimate (
    intake_artifact_plan_estimate_id uuid NOT NULL DEFAULT uuidv7(),
    plan_id                          uuid NOT NULL,
    scenario_label                   text NOT NULL DEFAULT 'expected',
    scenario_notes                   text,
    proposed_model_id                uuid,
    purpose_text                     text,
    expected_input_size_tokens       integer,
    expected_output_size_tokens      integer,
    expected_invocations_per_year    integer,
    peak_multiplier                  numeric(6,2)  NOT NULL DEFAULT 1.00,
    seasonality_pattern_text         text,
    expected_tool_call_count         integer       NOT NULL DEFAULT 0,
    expected_input_file              boolean       NOT NULL DEFAULT false,
    expected_input_file_avg_kb       integer,
    expected_input_file_max_kb       integer,
    cost_estimate_per_invocation_usd numeric(14,6),
    cost_estimate_yearly_usd         numeric(14,2),
    estimate_basis                   jsonb,
    cost_override_yearly_usd         numeric(14,2),
    cost_override_explanation        text,
    is_active                        boolean       NOT NULL DEFAULT true,
    created_by_user_id               uuid          NOT NULL,   -- replaces v1 created_by + acting_as_role (FR-018)
    created_at                       timestamptz   NOT NULL DEFAULT now(),
    updated_at                       timestamptz   NOT NULL DEFAULT now(),
    CONSTRAINT pk_intake_artifact_plan_estimate PRIMARY KEY (intake_artifact_plan_estimate_id),
    CONSTRAINT fk_intake_artifact_plan_estimate_plan
        FOREIGN KEY (plan_id)
        REFERENCES governance.intake_artifact_plan (intake_artifact_plan_id) ON DELETE CASCADE,
    CONSTRAINT fk_intake_artifact_plan_estimate_model
        FOREIGN KEY (proposed_model_id)
        REFERENCES governance.model (model_id) ON DELETE RESTRICT,
    CONSTRAINT ck_intake_artifact_plan_estimate_override_pair
        CHECK ((cost_override_yearly_usd IS NULL) = (cost_override_explanation IS NULL))
);
COMMENT ON TABLE governance.intake_artifact_plan_estimate IS
    'tier:1 — scenario-level cost forecast per plan row. Hardened from v1: created_by_user_id replaces self-asserted created_by/acting_as_role (FR-018). At most one active scenario per plan.';
CREATE UNIQUE INDEX uq_intake_artifact_plan_estimate_active
    ON governance.intake_artifact_plan_estimate (plan_id) WHERE is_active = true;
CREATE INDEX ix_intake_artifact_plan_estimate_plan_id
    ON governance.intake_artifact_plan_estimate (plan_id);

CREATE TABLE governance.intake_roi_assessment (
    intake_roi_assessment_id        uuid NOT NULL DEFAULT uuidv7(),
    intake_id                       uuid NOT NULL,
    scenario_label                  text NOT NULL DEFAULT 'expected',
    scenario_notes                  text,
    labor_hours_saved_per_year      numeric(12,2),
    loaded_labor_cost_per_hour_usd  numeric(10,2),
    annual_premium_in_scope_usd     numeric(14,2),
    loss_ratio_improvement_pp       numeric(6,3),
    submission_volume_per_year      integer,
    bind_rate_uplift_pp             numeric(6,3),
    avg_premium_per_bound_usd       numeric(12,2),
    risk_avoidance_yearly_usd       numeric(14,2),
    risk_avoidance_basis            text,
    other_benefit_label             text,
    other_benefit_yearly_usd        numeric(14,2),
    ai_spend_yearly_usd             numeric(14,2),
    ai_spend_basis                  text          NOT NULL DEFAULT 'cost_envelope',
    hitl_oversight_fte              numeric(6,2),
    hitl_loaded_cost_per_fte_usd    numeric(12,2),
    infrastructure_yearly_usd       numeric(12,2),
    build_cost_one_time_usd         numeric(14,2),
    horizon_years                   numeric(4,1)  NOT NULL DEFAULT 3.0,
    discount_rate_pct               numeric(5,2)  NOT NULL DEFAULT 10.00,
    labor_savings_yearly_usd        numeric(14,2),
    loss_ratio_savings_yearly_usd   numeric(14,2),
    premium_uplift_yearly_usd       numeric(14,2),
    total_benefit_yearly_usd        numeric(14,2),
    total_run_cost_yearly_usd       numeric(14,2),
    net_annual_benefit_usd          numeric(14,2),
    payback_period_months           numeric(6,2),
    npv_horizon_usd                 numeric(14,2),
    roi_pct                         numeric(8,2),
    is_active                       boolean       NOT NULL DEFAULT true,
    locked_at                       timestamptz,
    locked_by_user_id               uuid,                       -- replaces v1 locked_by + locked_role (FR-018)
    approval_request_id             uuid,
    created_by_user_id              uuid          NOT NULL,
    created_at                      timestamptz   NOT NULL DEFAULT now(),
    updated_at                      timestamptz   NOT NULL DEFAULT now(),
    CONSTRAINT pk_intake_roi_assessment PRIMARY KEY (intake_roi_assessment_id),
    CONSTRAINT fk_intake_roi_assessment_intake
        FOREIGN KEY (intake_id)
        REFERENCES governance.intake (intake_id) ON DELETE CASCADE,
    CONSTRAINT fk_intake_roi_assessment_approval_request
        FOREIGN KEY (approval_request_id)
        REFERENCES governance.approval_request (approval_request_id) ON DELETE RESTRICT,
    CONSTRAINT ck_intake_roi_assessment_lock_pair
        CHECK ((locked_at IS NULL) = (locked_by_user_id IS NULL))
);
COMMENT ON TABLE governance.intake_roi_assessment IS
    'tier:1 — intake-level ROI/business case. Hardened from v1: locked_by_user_id replaces self-asserted locked_by/locked_role (FR-018); lock pair invariant. At most one active scenario per intake.';
CREATE UNIQUE INDEX uq_intake_roi_assessment_active
    ON governance.intake_roi_assessment (intake_id) WHERE is_active = true;
CREATE INDEX ix_intake_roi_assessment_intake_id
    ON governance.intake_roi_assessment (intake_id);

CREATE TABLE governance.intake_cost_envelope (
    intake_cost_envelope_id    uuid          NOT NULL DEFAULT uuidv7(),
    intake_id                  uuid          NOT NULL,
    total_yearly_estimate_usd  numeric(14,2) NOT NULL,
    upside_pct                 numeric(5,2)  NOT NULL DEFAULT 20.00,
    total_yearly_envelope_usd  numeric(14,2) NOT NULL,
    any_row_override           boolean       NOT NULL DEFAULT false,
    locked_at                  timestamptz   NOT NULL DEFAULT now(),
    locked_by_user_id          uuid          NOT NULL,            -- replaces v1 locked_by + locked_role (FR-018)
    approval_request_id        uuid,
    notes                      text,
    CONSTRAINT pk_intake_cost_envelope PRIMARY KEY (intake_cost_envelope_id),
    CONSTRAINT fk_intake_cost_envelope_intake
        FOREIGN KEY (intake_id)
        REFERENCES governance.intake (intake_id) ON DELETE CASCADE,
    CONSTRAINT fk_intake_cost_envelope_approval_request
        FOREIGN KEY (approval_request_id)
        REFERENCES governance.approval_request (approval_request_id) ON DELETE RESTRICT,
    CONSTRAINT uq_intake_cost_envelope_intake UNIQUE (intake_id),  -- one locked envelope per intake
    CONSTRAINT ck_intake_cost_envelope_upside_nonneg CHECK (upside_pct >= 0)
);
COMMENT ON TABLE governance.intake_cost_envelope IS
    'tier:1 — locked spend cap, one row per intake. Hardened from v1: locked_by_user_id replaces self-asserted locked_by/locked_role (FR-018).';
CREATE INDEX ix_intake_cost_envelope_intake_id
    ON governance.intake_cost_envelope (intake_id);

-- ---------------------------------------------------------------------
-- 8. RUN DISPATCH OUTBOX  (V2-NEW, PCR 3.3 transactional outbox)
--    Inserted in the SAME txn as runtime.execution_run. verity-relay reads
--    pending rows (SKIP LOCKED), publishes to NATS, marks published.
-- ---------------------------------------------------------------------
CREATE TABLE governance.run_dispatch_outbox (
    run_dispatch_outbox_id uuid                    NOT NULL DEFAULT uuidv7(),
    execution_run_id       uuid                    NOT NULL,         -- runtime.execution_run PK (cross-schema; app-validated)
    subject                text                    NOT NULL,         -- NATS subject, e.g. verity.runs.pending
    payload                jsonb                   NOT NULL,
    status                 governance.outbox_status NOT NULL DEFAULT 'pending',
    published_at           timestamptz,
    claimed_at             timestamptz,
    attempt_count          integer NOT NULL DEFAULT 0,
    last_error             text,
    created_at             timestamptz NOT NULL DEFAULT now(),
    CONSTRAINT pk_run_dispatch_outbox PRIMARY KEY (run_dispatch_outbox_id),
    CONSTRAINT uq_run_dispatch_outbox_run UNIQUE (execution_run_id),
    CONSTRAINT ck_run_dispatch_outbox_published_at
        CHECK ((status = 'pending') OR (published_at IS NOT NULL)),
    CONSTRAINT ck_run_dispatch_outbox_attempts_nonneg CHECK (attempt_count >= 0)
);
COMMENT ON TABLE governance.run_dispatch_outbox IS
    'tier:1 — transactional outbox for run dispatch (PCR 3.3). One row per execution_run, inserted in the same txn. Relay publishes pending rows to NATS via SKIP LOCKED.';
-- Hot path for the relay: claim pending rows oldest-first.
CREATE INDEX ix_run_dispatch_outbox_pending
    ON governance.run_dispatch_outbox (created_at) WHERE status = 'pending';
