-- 10-validation.sql — hardened v2 schema domain: validation / testing / ground-truth
-- See ASSEMBLY-AND-VERIFICATION.md for cross-domain FKs & review items.
-- Closes Critical C9 (no-silent-capability-loss: GT/test/validation subsystem) and
-- C10 (analytics.v_validation_result source = runtime.test_execution_log).
--
-- FULL DDL lives at /home/avenugopal/projects/verity/specs/schema/10-validation.sql
-- (reproduced verbatim below).

-- =============================================================================
-- DOMAIN: TESTING / GROUND-TRUTH / VALIDATION / EVALUATION / MODEL-CARDS /
--         INCIDENTS / SIMILARITY / PLATFORM-SETTINGS
--   governance -> Tier-1 SoR (test catalog, GT assets, thresholds, configs,
--                 model cards, incidents, platform settings).
--   runtime    -> Tier-2 append-only logs (test_execution_log, validation_run +
--                 results, evaluation_run, description_similarity_log).
--   analytics  -> v_validation_result over runtime.test_execution_log (C10).
-- Hardening: ADR-0005/0004. KEY GENERATOR: uuidv7(). Cross-domain refs are SOFT
--   (no DB FK across schemas/tiers); hard FKs only within this domain.
-- ENUM REUSE (ENTITIES domain): governance.entity_type, metric_type,
--   materiality_tier, deployment_channel (referenced, NOT re-declared here).
-- =============================================================================

-- ---- ENUM TYPES (owned by THIS domain) -------------------------------------
CREATE TYPE governance.gt_dataset_status AS ENUM (
    'collecting','labeling','adjudicating','ready','deprecated');
CREATE TYPE governance.gt_quality_tier AS ENUM ('silver','gold');
CREATE TYPE governance.gt_source_type AS ENUM ('document','submission','synthetic');
CREATE TYPE governance.gt_annotator_type AS ENUM ('human_sme','llm_judge','adjudicator');
CREATE TYPE governance.mock_kind AS ENUM ('tool','source','target');
CREATE TYPE governance.validation_run_status AS ENUM ('running','complete','failed');
CREATE TYPE governance.validation_match_type AS ENUM ('exact','partial','fuzzy');
CREATE TYPE governance.extraction_field_type AS ENUM ('string','numeric','date','boolean','enum');
CREATE TYPE governance.extraction_match_type AS ENUM ('exact','numeric_tolerance','case_insensitive','contains');
CREATE TYPE governance.tolerance_unit AS ENUM ('percent','absolute');
CREATE TYPE governance.incident_severity AS ENUM ('critical','high','medium','low');
CREATE TYPE governance.incident_status AS ENUM ('open','investigating','mitigated','resolved','closed');
CREATE TYPE governance.evaluation_type AS ENUM ('shadow','challenger','periodic','drift_check');
CREATE TYPE governance.model_card_state AS ENUM ('draft','in_review','approved','superseded');
CREATE TYPE governance.setting_input_type AS ENUM ('text','select','number');

-- ---- TIER-1 (governance): TEST SUITE / CASE / MOCK -------------------------
CREATE TABLE governance.test_suite (
    test_suite_id       uuid                    NOT NULL DEFAULT uuidv7(),
    entity_type         governance.entity_type  NOT NULL,
    entity_id           uuid                    NOT NULL,  -- soft ref -> agent/task; no DB FK
    name                text                    NOT NULL,
    description         text,
    suite_type          text                    NOT NULL,
    created_by_user_id  uuid,                              -- soft ref -> account_user; no DB FK
    active              boolean                 NOT NULL DEFAULT true,
    created_at          timestamptz             NOT NULL DEFAULT now(),
    CONSTRAINT pk_test_suite PRIMARY KEY (test_suite_id),
    CONSTRAINT ck_test_suite_entity_kind CHECK (entity_type IN ('agent','task')),
    CONSTRAINT ck_test_suite_name_not_blank CHECK (length(btrim(name)) > 0));
CREATE INDEX ix_test_suite_entity ON governance.test_suite (entity_type, entity_id);
CREATE INDEX ix_test_suite_active ON governance.test_suite (active);

CREATE TABLE governance.test_case (
    test_case_id        uuid                    NOT NULL DEFAULT uuidv7(),
    test_suite_id       uuid                    NOT NULL,
    name                text                    NOT NULL,
    description         text,
    input_data          jsonb                   NOT NULL,
    expected_output     jsonb                   NOT NULL,
    metric_type         governance.metric_type  NOT NULL,
    metric_config       jsonb,
    applies_to_versions uuid[]                  NOT NULL DEFAULT '{}',  -- soft refs; no DB FK
    excludes_versions   uuid[]                  NOT NULL DEFAULT '{}',  -- soft refs; no DB FK
    is_adversarial      boolean                 NOT NULL DEFAULT false,
    tags                text[]                  NOT NULL DEFAULT '{}',
    active              boolean                 NOT NULL DEFAULT true,
    created_at          timestamptz             NOT NULL DEFAULT now(),
    CONSTRAINT pk_test_case PRIMARY KEY (test_case_id),
    CONSTRAINT fk_test_case_test_suite FOREIGN KEY (test_suite_id)
        REFERENCES governance.test_suite (test_suite_id) ON DELETE CASCADE,
    CONSTRAINT ck_test_case_name_not_blank CHECK (length(btrim(name)) > 0));
CREATE INDEX ix_test_case_test_suite ON governance.test_case (test_suite_id);
CREATE INDEX ix_test_case_tags ON governance.test_case USING gin (tags);

CREATE TABLE governance.test_case_mock (
    test_case_mock_id   uuid                    NOT NULL DEFAULT uuidv7(),
    test_case_id        uuid                    NOT NULL,
    mock_kind           governance.mock_kind    NOT NULL DEFAULT 'tool',
    mock_key            text                    NOT NULL,
    call_order          integer                 NOT NULL DEFAULT 1,
    mock_response       jsonb                   NOT NULL,
    description         text,
    created_at          timestamptz             NOT NULL DEFAULT now(),
    CONSTRAINT pk_test_case_mock PRIMARY KEY (test_case_mock_id),
    CONSTRAINT fk_test_case_mock_test_case FOREIGN KEY (test_case_id)
        REFERENCES governance.test_case (test_case_id) ON DELETE CASCADE,
    CONSTRAINT ck_test_case_mock_call_order_positive CHECK (call_order >= 1));
CREATE INDEX ix_test_case_mock_test_case ON governance.test_case_mock (test_case_id);
CREATE INDEX ix_test_case_mock_test_case_kind ON governance.test_case_mock (test_case_id, mock_kind);

-- ---- TIER-2 (runtime): TEST EXECUTION LOG (source for analytics.v_validation_result, C10)
CREATE TABLE runtime.test_execution_log (
    test_execution_log_id       uuid                        NOT NULL DEFAULT uuidv7(),
    test_suite_id               uuid                        NOT NULL,  -- soft ref Tier-1->Tier-2; no DB FK
    test_case_id                uuid                        NOT NULL,  -- soft ref; no DB FK
    entity_type                 governance.entity_type      NOT NULL,
    entity_version_id           uuid                        NOT NULL,  -- soft ref; no DB FK
    mock_mode                   boolean                     NOT NULL,
    channel                     governance.deployment_channel,
    input_used                  jsonb,
    actual_output               jsonb,
    expected_output             jsonb,
    metric_type                 governance.metric_type      NOT NULL,
    metric_result               jsonb,
    passed                      boolean                     NOT NULL,
    failure_reason              text,
    duration_ms                 integer,
    inference_config_snapshot   jsonb,
    run_at                      timestamptz                 NOT NULL DEFAULT now(),
    CONSTRAINT pk_test_execution_log PRIMARY KEY (test_execution_log_id),
    CONSTRAINT ck_test_execution_log_duration_nonneg CHECK (duration_ms IS NULL OR duration_ms >= 0));
CREATE INDEX ix_test_execution_log_entity ON runtime.test_execution_log (entity_type, entity_version_id);
CREATE INDEX ix_test_execution_log_suite ON runtime.test_execution_log (test_suite_id);
CREATE INDEX brin_test_execution_log_run_at ON runtime.test_execution_log USING brin (run_at);

-- ---- TIER-1 (governance): GROUND TRUTH dataset -> record -> annotation ------
CREATE TABLE governance.ground_truth_dataset (
    ground_truth_dataset_id     uuid                        NOT NULL DEFAULT uuidv7(),
    entity_type                 governance.entity_type      NOT NULL,
    entity_id                   uuid                        NOT NULL,  -- soft ref; no DB FK
    designed_for_version_id     uuid,                                  -- soft ref; no DB FK
    name                        text                        NOT NULL,
    version                     text                        NOT NULL DEFAULT '1.0',
    description                 text,
    purpose                     text                        NOT NULL,
    quality_tier                governance.gt_quality_tier  NOT NULL DEFAULT 'silver',
    status                      governance.gt_dataset_status NOT NULL DEFAULT 'collecting',
    labeling_guide_provider     text,
    labeling_guide_container    text,
    labeling_guide_key          text,
    owner_name                  text                        NOT NULL,
    created_by_user_id          uuid,                                  -- soft ref; no DB FK
    record_count                integer                     NOT NULL DEFAULT 0,
    annotated_count             integer                     NOT NULL DEFAULT 0,
    authoritative_count         integer                     NOT NULL DEFAULT 0,
    iaa_score                   numeric(5,4),
    iaa_computed_at             timestamptz,
    iaa_method                  text,
    coverage_notes              text,
    applies_to_versions         uuid[]                      NOT NULL DEFAULT '{}',  -- soft refs; no DB FK
    superseded_by_dataset_id    uuid,
    created_at                  timestamptz                 NOT NULL DEFAULT now(),
    updated_at                  timestamptz                 NOT NULL DEFAULT now(),
    CONSTRAINT pk_ground_truth_dataset PRIMARY KEY (ground_truth_dataset_id),
    CONSTRAINT uq_ground_truth_dataset_entity_name_version UNIQUE (entity_type, entity_id, name, version),
    CONSTRAINT fk_ground_truth_dataset_superseded_by FOREIGN KEY (superseded_by_dataset_id)
        REFERENCES governance.ground_truth_dataset (ground_truth_dataset_id) ON DELETE SET NULL,
    CONSTRAINT ck_ground_truth_dataset_entity_kind CHECK (entity_type IN ('agent','task')),
    CONSTRAINT ck_ground_truth_dataset_counts_nonneg CHECK (record_count >= 0 AND annotated_count >= 0 AND authoritative_count >= 0),
    CONSTRAINT ck_ground_truth_dataset_iaa_range CHECK (iaa_score IS NULL OR (iaa_score >= 0 AND iaa_score <= 1)));
CREATE INDEX ix_ground_truth_dataset_entity ON governance.ground_truth_dataset (entity_type, entity_id);
CREATE INDEX ix_ground_truth_dataset_status ON governance.ground_truth_dataset (status);
CREATE INDEX ix_ground_truth_dataset_superseded_by ON governance.ground_truth_dataset (superseded_by_dataset_id);

CREATE TABLE governance.ground_truth_record (
    ground_truth_record_id      uuid                        NOT NULL DEFAULT uuidv7(),
    ground_truth_dataset_id     uuid                        NOT NULL,
    record_index                integer                     NOT NULL,
    source_type                 governance.gt_source_type   NOT NULL,
    source_provider             text,
    source_container            text,
    source_key                  text,
    source_description          text,
    input_data                  jsonb                       NOT NULL,
    tags                        text[]                      NOT NULL DEFAULT '{}',
    difficulty                  text,
    record_notes                text,
    created_at                  timestamptz                 NOT NULL DEFAULT now(),
    CONSTRAINT pk_ground_truth_record PRIMARY KEY (ground_truth_record_id),
    CONSTRAINT uq_ground_truth_record_dataset_index UNIQUE (ground_truth_dataset_id, record_index),
    CONSTRAINT fk_ground_truth_record_dataset FOREIGN KEY (ground_truth_dataset_id)
        REFERENCES governance.ground_truth_dataset (ground_truth_dataset_id) ON DELETE CASCADE);
CREATE INDEX ix_ground_truth_record_dataset ON governance.ground_truth_record (ground_truth_dataset_id);
CREATE INDEX ix_ground_truth_record_tags ON governance.ground_truth_record USING gin (tags);

CREATE TABLE governance.ground_truth_record_mock (
    ground_truth_record_mock_id uuid                    NOT NULL DEFAULT uuidv7(),
    ground_truth_record_id      uuid                    NOT NULL,
    mock_kind                   governance.mock_kind    NOT NULL DEFAULT 'tool',
    mock_key                    text                    NOT NULL,
    call_order                  integer                 NOT NULL DEFAULT 1,
    mock_response               jsonb                   NOT NULL,
    description                 text,
    created_at                  timestamptz             NOT NULL DEFAULT now(),
    CONSTRAINT pk_ground_truth_record_mock PRIMARY KEY (ground_truth_record_mock_id),
    CONSTRAINT fk_ground_truth_record_mock_record FOREIGN KEY (ground_truth_record_id)
        REFERENCES governance.ground_truth_record (ground_truth_record_id) ON DELETE CASCADE,
    CONSTRAINT ck_ground_truth_record_mock_call_order_positive CHECK (call_order >= 1));
CREATE INDEX ix_ground_truth_record_mock_record ON governance.ground_truth_record_mock (ground_truth_record_id);
CREATE INDEX ix_ground_truth_record_mock_record_kind ON governance.ground_truth_record_mock (ground_truth_record_id, mock_kind);

CREATE TABLE governance.ground_truth_annotation (
    ground_truth_annotation_id  uuid                        NOT NULL DEFAULT uuidv7(),
    ground_truth_record_id      uuid                        NOT NULL,
    ground_truth_dataset_id     uuid                        NOT NULL,
    annotator_type              governance.gt_annotator_type NOT NULL,
    labeled_by_user_id          uuid,                                  -- soft ref; no DB FK
    label_confidence            numeric(5,4),
    label_notes                 text,
    judge_model                 text,
    judge_prompt_version_id     uuid,                                  -- v1 hard FK -> soft ref (cross-domain)
    judge_reasoning             text,
    expected_output             jsonb                       NOT NULL,
    is_authoritative            boolean                     NOT NULL DEFAULT false,
    is_corrected                boolean                     NOT NULL DEFAULT false,
    original_output             jsonb,
    corrected_at                timestamptz,
    correction_reason           text,
    labeled_at                  timestamptz                 NOT NULL DEFAULT now(),
    CONSTRAINT pk_ground_truth_annotation PRIMARY KEY (ground_truth_annotation_id),
    CONSTRAINT fk_ground_truth_annotation_record FOREIGN KEY (ground_truth_record_id)
        REFERENCES governance.ground_truth_record (ground_truth_record_id) ON DELETE CASCADE,
    CONSTRAINT fk_ground_truth_annotation_dataset FOREIGN KEY (ground_truth_dataset_id)
        REFERENCES governance.ground_truth_dataset (ground_truth_dataset_id) ON DELETE CASCADE,
    CONSTRAINT ck_ground_truth_annotation_human_attribution
        CHECK (annotator_type NOT IN ('human_sme','adjudicator') OR labeled_by_user_id IS NOT NULL),
    CONSTRAINT ck_ground_truth_annotation_judge_attribution
        CHECK (annotator_type <> 'llm_judge' OR judge_model IS NOT NULL),
    CONSTRAINT ck_ground_truth_annotation_confidence_range
        CHECK (label_confidence IS NULL OR (label_confidence >= 0 AND label_confidence <= 1)));
CREATE INDEX ix_ground_truth_annotation_record ON governance.ground_truth_annotation (ground_truth_record_id);
CREATE INDEX ix_ground_truth_annotation_dataset ON governance.ground_truth_annotation (ground_truth_dataset_id);
CREATE INDEX ix_ground_truth_annotation_annotator_type ON governance.ground_truth_annotation (annotator_type);
-- V2-NEW DB invariant: at most one authoritative annotation per record.
CREATE UNIQUE INDEX uq_ground_truth_annotation_authoritative_per_record
    ON governance.ground_truth_annotation (ground_truth_record_id) WHERE is_authoritative = true;

-- ---- TIER-2 (runtime): VALIDATION RUN + PER-RECORD RESULT ------------------
CREATE TABLE runtime.validation_run (
    validation_run_id           uuid                            NOT NULL DEFAULT uuidv7(),
    entity_type                 governance.entity_type          NOT NULL,
    entity_version_id           uuid                            NOT NULL,  -- soft ref; no DB FK
    ground_truth_dataset_id     uuid                            NOT NULL,  -- soft ref Tier-1->Tier-2; no DB FK
    dataset_version             text,
    run_by_user_id              uuid,                                      -- soft ref; no DB FK
    precision_score             numeric(7,6),
    recall_score                numeric(7,6),
    f1_score                    numeric(7,6),
    cohens_kappa                numeric(7,6),
    confusion_matrix            jsonb,
    field_accuracy              jsonb,
    overall_extraction_rate     numeric(7,6),
    low_confidence_rate         numeric(7,6),
    fairness_metrics            jsonb,
    fairness_passed             boolean,
    fairness_notes              text,
    thresholds_met              boolean,
    threshold_details           jsonb,
    sme_review_notes            text,
    sme_reviewed_by_user_id     uuid,                                      -- soft ref; no DB FK
    sme_reviewed_at             timestamptz,
    inference_config_snapshot   jsonb,
    status                      governance.validation_run_status NOT NULL DEFAULT 'running',
    passed                      boolean,
    notes                       text,
    run_at                      timestamptz                     NOT NULL DEFAULT now(),
    CONSTRAINT pk_validation_run PRIMARY KEY (validation_run_id),
    CONSTRAINT ck_validation_run_entity_kind CHECK (entity_type IN ('agent','task')));
CREATE INDEX ix_validation_run_entity ON runtime.validation_run (entity_type, entity_version_id);
CREATE INDEX ix_validation_run_dataset ON runtime.validation_run (ground_truth_dataset_id);
CREATE INDEX brin_validation_run_run_at ON runtime.validation_run USING brin (run_at);

CREATE TABLE runtime.validation_record_result (
    validation_record_result_id uuid                            NOT NULL DEFAULT uuidv7(),
    validation_run_id           uuid                            NOT NULL,
    ground_truth_record_id      uuid                            NOT NULL,  -- soft ref Tier-1->Tier-2; no DB FK
    record_index                integer                         NOT NULL,
    expected_output             jsonb                           NOT NULL,
    actual_output               jsonb                           NOT NULL,
    confidence                  numeric(5,4),
    correct                     boolean                         NOT NULL,
    match_type                  governance.validation_match_type,
    match_score                 numeric(7,6),
    field_results               jsonb,
    decision_log_id             uuid,                                      -- soft ref -> agent_decision_log; no DB FK
    duration_ms                 integer,
    created_at                  timestamptz                     NOT NULL DEFAULT now(),
    CONSTRAINT pk_validation_record_result PRIMARY KEY (validation_record_result_id),
    CONSTRAINT uq_validation_record_result_run_index UNIQUE (validation_run_id, record_index),
    CONSTRAINT fk_validation_record_result_run FOREIGN KEY (validation_run_id)
        REFERENCES runtime.validation_run (validation_run_id) ON DELETE CASCADE,
    CONSTRAINT ck_validation_record_result_duration_nonneg CHECK (duration_ms IS NULL OR duration_ms >= 0),
    CONSTRAINT ck_validation_record_result_match_score_range CHECK (match_score IS NULL OR (match_score >= 0 AND match_score <= 1)));
CREATE INDEX ix_validation_record_result_run ON runtime.validation_record_result (validation_run_id);
CREATE INDEX ix_validation_record_result_run_correct ON runtime.validation_record_result (validation_run_id, correct);

-- ---- TIER-2 (runtime): EVALUATION RUN --------------------------------------
CREATE TABLE runtime.evaluation_run (
    evaluation_run_id           uuid                        NOT NULL DEFAULT uuidv7(),
    entity_type                 governance.entity_type      NOT NULL,
    entity_version_id           uuid                        NOT NULL,  -- soft ref; no DB FK
    evaluation_type             governance.evaluation_type  NOT NULL,
    run_period_start            timestamptz                 NOT NULL,
    run_period_end              timestamptz                 NOT NULL,
    champion_version_id         uuid,                                  -- soft ref; no DB FK
    total_invocations           integer                     NOT NULL DEFAULT 0,
    successful_invocations      integer                     NOT NULL DEFAULT 0,
    failed_invocations          integer                     NOT NULL DEFAULT 0,
    agreement_rate              numeric(7,6),
    disagreement_examples       jsonb,
    avg_duration_ms             numeric(10,2),
    avg_input_tokens            numeric(10,2),
    avg_output_tokens           numeric(10,2),
    override_count              integer                     NOT NULL DEFAULT 0,
    override_rate               numeric(7,6),
    override_pattern_flags      jsonb,
    metric_drift_detected       boolean                     NOT NULL DEFAULT false,
    drift_details               jsonb,
    promotion_recommendation    text,
    created_at                  timestamptz                 NOT NULL DEFAULT now(),
    CONSTRAINT pk_evaluation_run PRIMARY KEY (evaluation_run_id),
    CONSTRAINT ck_evaluation_run_period_order CHECK (run_period_end >= run_period_start),
    CONSTRAINT ck_evaluation_run_counts_nonneg CHECK (total_invocations >= 0 AND successful_invocations >= 0 AND failed_invocations >= 0 AND override_count >= 0));
CREATE INDEX ix_evaluation_run_entity ON runtime.evaluation_run (entity_type, entity_version_id);
CREATE INDEX brin_evaluation_run_created_at ON runtime.evaluation_run USING brin (created_at);

-- ---- TIER-1 (governance): MODEL CARD / METRIC THRESHOLD / FIELD CONFIG -----
CREATE TABLE governance.model_card (
    model_card_id               uuid                        NOT NULL DEFAULT uuidv7(),
    entity_type                 governance.entity_type      NOT NULL,
    entity_version_id           uuid                        NOT NULL,  -- soft ref; no DB FK
    card_version                integer                     NOT NULL DEFAULT 1,
    purpose                     text                        NOT NULL,
    design_rationale            text                        NOT NULL,
    inputs_description          text                        NOT NULL,
    outputs_description         text                        NOT NULL,
    known_limitations           text                        NOT NULL,
    conditions_of_use           text                        NOT NULL,
    lm_specific_limitations     text,
    prompt_sensitivity_notes    text,
    validated_by_user_id        uuid,                                  -- soft ref; no DB FK
    validation_run_id           uuid,                                  -- v1 hard FK -> soft ref (Tier-1->Tier-2)
    validation_notes            text,
    regulatory_notes            text,
    materiality_classification  text,
    approved_by_user_id         uuid,                                  -- soft ref; no DB FK
    approved_at                 timestamptz,
    card_state                  governance.model_card_state NOT NULL DEFAULT 'draft',
    created_at                  timestamptz                 NOT NULL DEFAULT now(),
    updated_at                  timestamptz                 NOT NULL DEFAULT now(),
    CONSTRAINT pk_model_card PRIMARY KEY (model_card_id),
    CONSTRAINT uq_model_card_entity_version_card_version UNIQUE (entity_type, entity_version_id, card_version),
    CONSTRAINT ck_model_card_entity_kind CHECK (entity_type IN ('agent','task')),
    CONSTRAINT ck_model_card_card_version_positive CHECK (card_version >= 1));
CREATE INDEX ix_model_card_entity ON governance.model_card (entity_type, entity_version_id);

CREATE TABLE governance.metric_threshold (
    metric_threshold_id     uuid                        NOT NULL DEFAULT uuidv7(),
    entity_type             governance.entity_type      NOT NULL,
    entity_id               uuid                        NOT NULL,  -- soft ref; no DB FK
    materiality_tier        governance.materiality_tier NOT NULL,
    metric_name             text                        NOT NULL,
    field_name              text,
    minimum_acceptable      numeric(7,6)                NOT NULL,
    target_champion         numeric(7,6)                NOT NULL,
    created_at              timestamptz                 NOT NULL DEFAULT now(),
    CONSTRAINT pk_metric_threshold PRIMARY KEY (metric_threshold_id),
    CONSTRAINT ck_metric_threshold_bounds CHECK (minimum_acceptable <= target_champion));
-- v1 nullable-field UNIQUE split into two partial unique indexes:
CREATE UNIQUE INDEX uq_metric_threshold_aggregate
    ON governance.metric_threshold (entity_type, entity_id, materiality_tier, metric_name) WHERE field_name IS NULL;
CREATE UNIQUE INDEX uq_metric_threshold_per_field
    ON governance.metric_threshold (entity_type, entity_id, materiality_tier, metric_name, field_name) WHERE field_name IS NOT NULL;
CREATE INDEX ix_metric_threshold_entity ON governance.metric_threshold (entity_type, entity_id);

CREATE TABLE governance.field_extraction_config (
    field_extraction_config_id  uuid                            NOT NULL DEFAULT uuidv7(),
    entity_type                 governance.entity_type          NOT NULL,
    entity_id                   uuid                            NOT NULL,  -- soft ref; no DB FK
    field_name                  text                            NOT NULL,
    field_type                  governance.extraction_field_type NOT NULL,
    match_type                  governance.extraction_match_type NOT NULL,
    tolerance_value             numeric(10,4),
    tolerance_unit              governance.tolerance_unit,
    is_required                 boolean                         NOT NULL DEFAULT true,
    created_at                  timestamptz                     NOT NULL DEFAULT now(),
    CONSTRAINT pk_field_extraction_config PRIMARY KEY (field_extraction_config_id),
    CONSTRAINT uq_field_extraction_config_entity_field UNIQUE (entity_type, entity_id, field_name),
    CONSTRAINT ck_field_extraction_config_task_only CHECK (entity_type = 'task'),
    CONSTRAINT ck_field_extraction_config_tolerance_unit_when_numeric
        CHECK (match_type <> 'numeric_tolerance' OR tolerance_unit IS NOT NULL));
CREATE INDEX ix_field_extraction_config_entity ON governance.field_extraction_config (entity_type, entity_id);

-- ---- TIER-2 (runtime): DESCRIPTION SIMILARITY LOG --------------------------
CREATE TABLE runtime.description_similarity_log (
    description_similarity_log_id uuid                      NOT NULL DEFAULT uuidv7(),
    checked_entity_type         governance.entity_type      NOT NULL,
    checked_entity_id           uuid                        NOT NULL,  -- soft ref; no DB FK
    checked_entity_name         text                        NOT NULL,
    similar_entity_type         governance.entity_type      NOT NULL,
    similar_entity_id           uuid                        NOT NULL,  -- soft ref; no DB FK
    similar_entity_name         text                        NOT NULL,
    similarity_score            numeric(7,6)                NOT NULL,
    flagged                     boolean GENERATED ALWAYS AS (similarity_score > 0.85) STORED,
    reviewed_at                 timestamptz,
    reviewed_by_user_id         uuid,                                  -- soft ref; no DB FK
    resolution                  text,
    resolution_notes            text,
    checked_at                  timestamptz                 NOT NULL DEFAULT now(),
    CONSTRAINT pk_description_similarity_log PRIMARY KEY (description_similarity_log_id),
    CONSTRAINT ck_description_similarity_log_score_range CHECK (similarity_score >= 0 AND similarity_score <= 1));
CREATE INDEX ix_description_similarity_log_checked_entity ON runtime.description_similarity_log (checked_entity_type, checked_entity_id);
CREATE INDEX brin_description_similarity_log_checked_at ON runtime.description_similarity_log USING brin (checked_at);

-- ---- TIER-1 (governance): INCIDENT -----------------------------------------
CREATE TABLE governance.incident (
    incident_id             uuid                            NOT NULL DEFAULT uuidv7(),
    entity_type             governance.entity_type          NOT NULL,
    entity_id               uuid                            NOT NULL,  -- soft ref; no DB FK
    entity_version_id       uuid,                                      -- soft ref; no DB FK
    title                   text                            NOT NULL,
    description             text                            NOT NULL,
    severity                governance.incident_severity    NOT NULL,
    detection_source        text,
    detected_at             timestamptz                     NOT NULL DEFAULT now(),
    affected_context_ids    uuid[]                          NOT NULL DEFAULT '{}',  -- soft refs; no DB FK
    affected_decision_count integer                         NOT NULL DEFAULT 0,
    rollback_executed       boolean                         NOT NULL DEFAULT false,
    rollback_to_version_id  uuid,                                      -- soft ref; no DB FK
    rollback_at             timestamptz,
    rollback_approved_by_user_id uuid,                                 -- soft ref; no DB FK
    resolution_notes        text,
    new_test_cases_added    integer                         NOT NULL DEFAULT 0,
    resolved_at             timestamptz,
    status                  governance.incident_status      NOT NULL DEFAULT 'open',
    created_at              timestamptz                     NOT NULL DEFAULT now(),
    CONSTRAINT pk_incident PRIMARY KEY (incident_id),
    CONSTRAINT ck_incident_title_not_blank CHECK (length(btrim(title)) > 0),
    CONSTRAINT ck_incident_counts_nonneg CHECK (affected_decision_count >= 0 AND new_test_cases_added >= 0),
    CONSTRAINT ck_incident_rollback_target_when_executed CHECK (rollback_executed = false OR rollback_to_version_id IS NOT NULL));
CREATE INDEX ix_incident_entity ON governance.incident (entity_type, entity_id);
CREATE INDEX ix_incident_status ON governance.incident (status);
CREATE INDEX ix_incident_severity ON governance.incident (severity);

-- ---- TIER-1 (governance): PLATFORM SETTINGS --------------------------------
CREATE TABLE governance.platform_settings (
    platform_settings_id    uuid                            NOT NULL DEFAULT uuidv7(),
    setting_key             text                            NOT NULL,  -- v1 reserved-word `key`
    setting_value           text                            NOT NULL,  -- v1 `value`
    category                text                            NOT NULL DEFAULT 'general',
    display_name            text,
    description             text,
    input_type              governance.setting_input_type   NOT NULL DEFAULT 'text',
    options                 text,
    sort_order              integer                         NOT NULL DEFAULT 0,
    updated_at              timestamptz                     NOT NULL DEFAULT now(),
    CONSTRAINT pk_platform_settings PRIMARY KEY (platform_settings_id),
    CONSTRAINT uq_platform_settings_setting_key UNIQUE (setting_key),
    CONSTRAINT ck_platform_settings_key_not_blank CHECK (length(btrim(setting_key)) > 0),
    CONSTRAINT ck_platform_settings_options_when_select CHECK (input_type <> 'select' OR options IS NOT NULL));
CREATE INDEX ix_platform_settings_category ON governance.platform_settings (category, sort_order);

-- ---- ANALYTICS VIEW (resolves C10) -----------------------------------------
CREATE VIEW analytics.v_validation_result AS
SELECT tel.test_execution_log_id, tel.test_suite_id, tel.test_case_id, tel.entity_type,
       tel.entity_version_id, tel.mock_mode, tel.channel, tel.metric_type, tel.metric_result,
       tel.passed, tel.failure_reason, tel.duration_ms, tel.run_at
FROM runtime.test_execution_log AS tel;
COMMENT ON VIEW analytics.v_validation_result IS
    'Resolves ASSEMBLY C10: logical-mart projection over runtime.test_execution_log. Source table now exists (C9 closure).';
