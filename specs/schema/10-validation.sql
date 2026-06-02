-- =====================================================================
-- 10-validation.sql — Verity v2 hardened schema · TESTING / GROUND-TRUTH /
-- VALIDATION / EVALUATION / MODEL-CARDS / INCIDENTS / PLATFORM-SETTINGS.
-- Closes the C9 no-silent-loss gap. Definitions/state in core; execution logs Tier-2.
-- Status workflows use mutable *_status_code (D4); attribution via actor (D6).
-- =====================================================================

-- ===== test suites / cases / mocks ===================================
CREATE TABLE core.test_suite (
    test_suite_id uuid NOT NULL DEFAULT uuidv7(), executable_id uuid NOT NULL,
    name text NOT NULL, description text, suite_type text NOT NULL, active boolean NOT NULL DEFAULT true,
    created_at timestamptz NOT NULL DEFAULT now(), created_by_actor_id uuid NOT NULL, created_role_code text NOT NULL,
    CONSTRAINT pk_test_suite PRIMARY KEY (test_suite_id),
    CONSTRAINT fk_test_suite_executable FOREIGN KEY (executable_id) REFERENCES core.executable (executable_id) ON DELETE RESTRICT,
    CONSTRAINT fk_test_suite_created_by FOREIGN KEY (created_by_actor_id) REFERENCES core.actor (actor_id),
    CONSTRAINT fk_test_suite_created_role FOREIGN KEY (created_role_code) REFERENCES reference.role (code));
COMMENT ON TABLE core.test_suite IS 'tier:1. A test suite for an executable (agent/task). D5/C9.';

CREATE TABLE core.test_case (
    test_case_id uuid NOT NULL DEFAULT uuidv7(), test_suite_id uuid NOT NULL,
    name text NOT NULL, description text, input_data jsonb NOT NULL, expected_output jsonb NOT NULL,
    metric_type_code text NOT NULL, metric_config jsonb,
    applies_to_versions uuid[] NOT NULL DEFAULT '{}', is_adversarial boolean NOT NULL DEFAULT false,
    tags text[] NOT NULL DEFAULT '{}', active boolean NOT NULL DEFAULT true, created_at timestamptz NOT NULL DEFAULT now(),
    CONSTRAINT pk_test_case PRIMARY KEY (test_case_id),
    CONSTRAINT fk_test_case_suite FOREIGN KEY (test_suite_id) REFERENCES core.test_suite (test_suite_id) ON DELETE CASCADE,
    CONSTRAINT fk_test_case_metric FOREIGN KEY (metric_type_code) REFERENCES reference.metric_type (code));
CREATE INDEX ix_test_case_suite ON core.test_case (test_suite_id);

CREATE TABLE core.test_case_mock (
    test_case_mock_id uuid NOT NULL DEFAULT uuidv7(), test_case_id uuid NOT NULL,
    mock_kind_code text NOT NULL DEFAULT 'tool', mock_key text NOT NULL, call_order integer NOT NULL DEFAULT 1,
    mock_response jsonb NOT NULL, description text, created_at timestamptz NOT NULL DEFAULT now(),
    CONSTRAINT pk_test_case_mock PRIMARY KEY (test_case_mock_id),
    CONSTRAINT fk_test_case_mock_case FOREIGN KEY (test_case_id) REFERENCES core.test_case (test_case_id) ON DELETE CASCADE,
    CONSTRAINT fk_test_case_mock_kind FOREIGN KEY (mock_kind_code) REFERENCES reference.mock_kind (code),
    CONSTRAINT ck_test_case_mock_order CHECK (call_order >= 1));

-- ===== ground truth ==================================================
CREATE TABLE core.ground_truth_dataset (
    ground_truth_dataset_id uuid NOT NULL DEFAULT uuidv7(), name text NOT NULL, description text,
    gt_dataset_status_code text NOT NULL DEFAULT 'collecting', gt_quality_tier_code text NOT NULL DEFAULT 'silver',
    gt_source_type_code text NOT NULL, labeling_guide text, iaa_score numeric(5,4),
    superseded_by_dataset_id uuid, created_at timestamptz NOT NULL DEFAULT now(), updated_at timestamptz NOT NULL DEFAULT now(),
    created_by_actor_id uuid NOT NULL, created_role_code text NOT NULL,
    CONSTRAINT pk_ground_truth_dataset PRIMARY KEY (ground_truth_dataset_id),
    CONSTRAINT fk_gtd_status FOREIGN KEY (gt_dataset_status_code) REFERENCES reference.gt_dataset_status (code),
    CONSTRAINT fk_gtd_quality FOREIGN KEY (gt_quality_tier_code) REFERENCES reference.gt_quality_tier (code),
    CONSTRAINT fk_gtd_source FOREIGN KEY (gt_source_type_code) REFERENCES reference.gt_source_type (code),
    CONSTRAINT fk_gtd_superseded FOREIGN KEY (superseded_by_dataset_id) REFERENCES core.ground_truth_dataset (ground_truth_dataset_id) ON DELETE SET NULL,
    CONSTRAINT fk_gtd_created_by FOREIGN KEY (created_by_actor_id) REFERENCES core.actor (actor_id),
    CONSTRAINT fk_gtd_created_role FOREIGN KEY (created_role_code) REFERENCES reference.role (code));
COMMENT ON TABLE core.ground_truth_dataset IS 'tier:1. A ground-truth dataset; status mutable (D4). C9.';

CREATE TABLE core.ground_truth_record (
    ground_truth_record_id uuid NOT NULL DEFAULT uuidv7(), ground_truth_dataset_id uuid NOT NULL,
    input_data jsonb NOT NULL, expected_output jsonb NOT NULL, created_at timestamptz NOT NULL DEFAULT now(),
    CONSTRAINT pk_ground_truth_record PRIMARY KEY (ground_truth_record_id),
    CONSTRAINT fk_gtr_dataset FOREIGN KEY (ground_truth_dataset_id) REFERENCES core.ground_truth_dataset (ground_truth_dataset_id) ON DELETE CASCADE);
CREATE INDEX ix_ground_truth_record_dataset ON core.ground_truth_record (ground_truth_dataset_id);

CREATE TABLE core.ground_truth_record_mock (
    ground_truth_record_mock_id uuid NOT NULL DEFAULT uuidv7(), ground_truth_record_id uuid NOT NULL,
    mock_kind_code text NOT NULL DEFAULT 'tool', mock_key text NOT NULL, mock_response jsonb NOT NULL,
    CONSTRAINT pk_ground_truth_record_mock PRIMARY KEY (ground_truth_record_mock_id),
    CONSTRAINT fk_gtrm_record FOREIGN KEY (ground_truth_record_id) REFERENCES core.ground_truth_record (ground_truth_record_id) ON DELETE CASCADE,
    CONSTRAINT fk_gtrm_kind FOREIGN KEY (mock_kind_code) REFERENCES reference.mock_kind (code));

CREATE TABLE core.ground_truth_annotation (
    ground_truth_annotation_id uuid NOT NULL DEFAULT uuidv7(), ground_truth_record_id uuid NOT NULL,
    gt_annotator_type_code text NOT NULL, annotator_actor_id uuid, annotation jsonb NOT NULL,
    is_authoritative boolean NOT NULL DEFAULT false, created_at timestamptz NOT NULL DEFAULT now(),
    CONSTRAINT pk_ground_truth_annotation PRIMARY KEY (ground_truth_annotation_id),
    CONSTRAINT fk_gta_record FOREIGN KEY (ground_truth_record_id) REFERENCES core.ground_truth_record (ground_truth_record_id) ON DELETE CASCADE,
    CONSTRAINT fk_gta_annotator_type FOREIGN KEY (gt_annotator_type_code) REFERENCES reference.gt_annotator_type (code),
    CONSTRAINT fk_gta_annotator_actor FOREIGN KEY (annotator_actor_id) REFERENCES core.actor (actor_id));
CREATE UNIQUE INDEX uq_gt_annotation_authoritative ON core.ground_truth_annotation (ground_truth_record_id) WHERE is_authoritative;

-- ===== validation & evaluation runs ==================================
CREATE TABLE core.validation_run (
    validation_run_id uuid NOT NULL DEFAULT uuidv7(), executable_version_id uuid NOT NULL,
    ground_truth_dataset_id uuid NOT NULL, validation_run_status_code text NOT NULL DEFAULT 'running',
    summary jsonb, started_at timestamptz NOT NULL DEFAULT now(), finished_at timestamptz,
    requested_by_actor_id uuid NOT NULL, requested_role_code text NOT NULL,
    CONSTRAINT pk_validation_run PRIMARY KEY (validation_run_id),
    CONSTRAINT fk_validation_run_version FOREIGN KEY (executable_version_id) REFERENCES core.executable_version (executable_version_id) ON DELETE RESTRICT,
    CONSTRAINT fk_validation_run_dataset FOREIGN KEY (ground_truth_dataset_id) REFERENCES core.ground_truth_dataset (ground_truth_dataset_id) ON DELETE RESTRICT,
    CONSTRAINT fk_validation_run_status FOREIGN KEY (validation_run_status_code) REFERENCES reference.validation_run_status (code),
    CONSTRAINT fk_validation_run_requested_by FOREIGN KEY (requested_by_actor_id) REFERENCES core.actor (actor_id),
    CONSTRAINT fk_validation_run_requested_role FOREIGN KEY (requested_role_code) REFERENCES reference.role (code));

CREATE TABLE core.validation_record_result (
    validation_record_result_id uuid NOT NULL DEFAULT uuidv7(), validation_run_id uuid NOT NULL,
    ground_truth_record_id uuid NOT NULL, validation_match_type_code text NOT NULL, passed boolean NOT NULL,
    score numeric(6,4), detail jsonb, created_at timestamptz NOT NULL DEFAULT now(),
    CONSTRAINT pk_validation_record_result PRIMARY KEY (validation_record_result_id),
    CONSTRAINT fk_vrr_run FOREIGN KEY (validation_run_id) REFERENCES core.validation_run (validation_run_id) ON DELETE CASCADE,
    CONSTRAINT fk_vrr_record FOREIGN KEY (ground_truth_record_id) REFERENCES core.ground_truth_record (ground_truth_record_id) ON DELETE RESTRICT,
    CONSTRAINT fk_vrr_match FOREIGN KEY (validation_match_type_code) REFERENCES reference.validation_match_type (code));

CREATE TABLE core.evaluation_run (
    evaluation_run_id uuid NOT NULL DEFAULT uuidv7(), executable_version_id uuid NOT NULL,
    evaluation_type_code text NOT NULL, summary jsonb, created_at timestamptz NOT NULL DEFAULT now(),
    requested_by_actor_id uuid NOT NULL, requested_role_code text NOT NULL,
    CONSTRAINT pk_evaluation_run PRIMARY KEY (evaluation_run_id),
    CONSTRAINT fk_evaluation_run_version FOREIGN KEY (executable_version_id) REFERENCES core.executable_version (executable_version_id) ON DELETE RESTRICT,
    CONSTRAINT fk_evaluation_run_type FOREIGN KEY (evaluation_type_code) REFERENCES reference.evaluation_type (code),
    CONSTRAINT fk_evaluation_run_requested_by FOREIGN KEY (requested_by_actor_id) REFERENCES core.actor (actor_id),
    CONSTRAINT fk_evaluation_run_requested_role FOREIGN KEY (requested_role_code) REFERENCES reference.role (code));

-- ===== model cards / thresholds / extraction config ==================
CREATE TABLE core.model_card (
    model_card_id uuid NOT NULL DEFAULT uuidv7(), executable_version_id uuid NOT NULL,
    model_card_state_code text NOT NULL DEFAULT 'draft', content jsonb NOT NULL,
    created_at timestamptz NOT NULL DEFAULT now(), updated_at timestamptz NOT NULL DEFAULT now(),
    created_by_actor_id uuid NOT NULL, created_role_code text NOT NULL,
    CONSTRAINT pk_model_card PRIMARY KEY (model_card_id),
    CONSTRAINT fk_model_card_version FOREIGN KEY (executable_version_id) REFERENCES core.executable_version (executable_version_id) ON DELETE RESTRICT,
    CONSTRAINT fk_model_card_state FOREIGN KEY (model_card_state_code) REFERENCES reference.model_card_state (code),
    CONSTRAINT fk_model_card_created_by FOREIGN KEY (created_by_actor_id) REFERENCES core.actor (actor_id),
    CONSTRAINT fk_model_card_created_role FOREIGN KEY (created_role_code) REFERENCES reference.role (code));
COMMENT ON TABLE core.model_card IS 'tier:1. Model-card review lifecycle; state mutable (D4). Distinct from the executable lifecycle. C9.';

CREATE TABLE core.metric_threshold (
    metric_threshold_id uuid NOT NULL DEFAULT uuidv7(), executable_version_id uuid,
    metric_type_code text NOT NULL, threshold numeric(8,4) NOT NULL, comparator text NOT NULL DEFAULT '>=',
    created_at timestamptz NOT NULL DEFAULT now(),
    CONSTRAINT pk_metric_threshold PRIMARY KEY (metric_threshold_id),
    CONSTRAINT fk_metric_threshold_version FOREIGN KEY (executable_version_id) REFERENCES core.executable_version (executable_version_id) ON DELETE CASCADE,
    CONSTRAINT fk_metric_threshold_metric FOREIGN KEY (metric_type_code) REFERENCES reference.metric_type (code));

CREATE TABLE core.field_extraction_config (
    field_extraction_config_id uuid NOT NULL DEFAULT uuidv7(), executable_version_id uuid NOT NULL,
    field_name text NOT NULL, extraction_field_type_code text NOT NULL, extraction_match_type_code text NOT NULL,
    tolerance numeric(8,4), tolerance_unit_code text, created_at timestamptz NOT NULL DEFAULT now(),
    CONSTRAINT pk_field_extraction_config PRIMARY KEY (field_extraction_config_id),
    CONSTRAINT fk_fec_version FOREIGN KEY (executable_version_id) REFERENCES core.executable_version (executable_version_id) ON DELETE CASCADE,
    CONSTRAINT fk_fec_field_type FOREIGN KEY (extraction_field_type_code) REFERENCES reference.extraction_field_type (code),
    CONSTRAINT fk_fec_match_type FOREIGN KEY (extraction_match_type_code) REFERENCES reference.extraction_match_type (code),
    CONSTRAINT fk_fec_tolerance_unit FOREIGN KEY (tolerance_unit_code) REFERENCES reference.tolerance_unit (code));

-- ===== incidents & platform settings =================================
CREATE TABLE core.incident (
    incident_id uuid NOT NULL DEFAULT uuidv7(), executable_version_id uuid,
    incident_severity_code text NOT NULL, incident_status_code text NOT NULL DEFAULT 'open',
    title text NOT NULL, description text, created_at timestamptz NOT NULL DEFAULT now(), updated_at timestamptz NOT NULL DEFAULT now(),
    opened_by_actor_id uuid NOT NULL, opened_role_code text NOT NULL,
    CONSTRAINT pk_incident PRIMARY KEY (incident_id),
    CONSTRAINT fk_incident_version FOREIGN KEY (executable_version_id) REFERENCES core.executable_version (executable_version_id) ON DELETE SET NULL,
    CONSTRAINT fk_incident_severity FOREIGN KEY (incident_severity_code) REFERENCES reference.incident_severity (code),
    CONSTRAINT fk_incident_status FOREIGN KEY (incident_status_code) REFERENCES reference.incident_status (code),
    CONSTRAINT fk_incident_opened_by FOREIGN KEY (opened_by_actor_id) REFERENCES core.actor (actor_id),
    CONSTRAINT fk_incident_opened_role FOREIGN KEY (opened_role_code) REFERENCES reference.role (code));
COMMENT ON TABLE core.incident IS 'tier:1. Governance incident; status mutable (D4). C9.';

CREATE TABLE core.platform_settings (
    setting_key text NOT NULL, setting_input_type_code text NOT NULL, value jsonb NOT NULL,
    description text, updated_at timestamptz NOT NULL DEFAULT now(), updated_by_actor_id uuid,
    CONSTRAINT pk_platform_settings PRIMARY KEY (setting_key),
    CONSTRAINT fk_platform_settings_input_type FOREIGN KEY (setting_input_type_code) REFERENCES reference.setting_input_type (code),
    CONSTRAINT fk_platform_settings_updated_by FOREIGN KEY (updated_by_actor_id) REFERENCES core.actor (actor_id));

-- ===== AUDIT (Tier-2): test execution + similarity logs ==============
CREATE TABLE audit.test_execution_log (
    test_execution_log_id uuid NOT NULL DEFAULT uuidv7(),
    test_suite_id uuid, test_case_id uuid, executable_version_id uuid,    -- soft refs
    mock_mode boolean NOT NULL, metric_type_code text, metric_result jsonb,
    passed boolean NOT NULL, failure_reason text, duration_ms integer,
    actual_output jsonb, created_at timestamptz NOT NULL DEFAULT now(),
    CONSTRAINT pk_test_execution_log PRIMARY KEY (test_execution_log_id, created_at)
) PARTITION BY RANGE (created_at);
COMMENT ON TABLE audit.test_execution_log IS 'tier:2 append-only (partitioned). Per-test-case execution results. Soft refs to core. C9/C10.';
CREATE INDEX ix_test_execution_log_version_time ON audit.test_execution_log (executable_version_id, created_at DESC);
CREATE TABLE audit.test_execution_log_2026_06 PARTITION OF audit.test_execution_log FOR VALUES FROM ('2026-06-01') TO ('2026-07-01');
CREATE TABLE audit.test_execution_log_2026_07 PARTITION OF audit.test_execution_log FOR VALUES FROM ('2026-07-01') TO ('2026-08-01');

CREATE TABLE audit.description_similarity_log (
    description_similarity_log_id uuid NOT NULL DEFAULT uuidv7(),
    subject_kind text NOT NULL, subject_id uuid NOT NULL,   -- soft polymorphic
    similar_to_id uuid NOT NULL, similarity numeric(6,5) NOT NULL, created_at timestamptz NOT NULL DEFAULT now(),
    CONSTRAINT pk_description_similarity_log PRIMARY KEY (description_similarity_log_id, created_at)
) PARTITION BY RANGE (created_at);
COMMENT ON TABLE audit.description_similarity_log IS 'tier:2 append-only (partitioned). pgvector similarity hits (dedup/recommendation). C9.';
CREATE TABLE audit.description_similarity_log_2026_06 PARTITION OF audit.description_similarity_log FOR VALUES FROM ('2026-06-01') TO ('2026-07-01');
CREATE TABLE audit.description_similarity_log_2026_07 PARTITION OF audit.description_similarity_log FOR VALUES FROM ('2026-07-01') TO ('2026-08-01');
