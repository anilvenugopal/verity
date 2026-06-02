-- audit.test_execution_log  ·  subject: validation  ·  (table)

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
