-- audit.test_execution_log  ·  subject: validation  ·  (table)

CREATE TABLE audit.test_execution_log (
    test_execution_log_id uuid NOT NULL DEFAULT uuidv7(),
    test_suite_id uuid, test_case_id uuid, executable_version_id uuid,    -- soft refs
    mock_mode boolean NOT NULL, metric_type_code text, metric_result jsonb,
    passed boolean NOT NULL, failure_reason text, duration_ms integer,
    actual_output jsonb, created_at timestamptz NOT NULL DEFAULT now(),
    CONSTRAINT pk_test_execution_log PRIMARY KEY (test_execution_log_id, created_at)
) PARTITION BY RANGE (created_at);
COMMENT ON TABLE audit.test_execution_log IS
'Append-only per-test-case execution results — whether it passed, the metric result, failure reason, latency, and actual output, with whether it ran in mock mode. Tier-2, partitioned, soft refs to core (C9/C10).

@tier 2
@lifecycle append-only
@subject validation
@partitioned RANGE(created_at)
@status reference.metric_type';
CREATE INDEX ix_test_execution_log_version_time ON audit.test_execution_log (executable_version_id, created_at DESC);
CREATE TABLE audit.test_execution_log_2026_06 PARTITION OF audit.test_execution_log FOR VALUES FROM ('2026-06-01') TO ('2026-07-01');
CREATE TABLE audit.test_execution_log_2026_07 PARTITION OF audit.test_execution_log FOR VALUES FROM ('2026-07-01') TO ('2026-08-01');
COMMENT ON COLUMN audit.test_execution_log.test_execution_log_id IS
'Identity of the result (with created_at, the partition key).';
COMMENT ON COLUMN audit.test_execution_log.test_suite_id IS
'The suite. @ref core.test_suite soft';
COMMENT ON COLUMN audit.test_execution_log.test_case_id IS
'The case. @ref core.test_case soft';
COMMENT ON COLUMN audit.test_execution_log.executable_version_id IS
'The version tested. @ref core.executable_version soft';
COMMENT ON COLUMN audit.test_execution_log.mock_mode IS
'Whether the case ran with mocks rather than live backends.';
COMMENT ON COLUMN audit.test_execution_log.metric_type_code IS
'How it was graded. @status reference.metric_type';
COMMENT ON COLUMN audit.test_execution_log.metric_result IS
'The metric output.';
COMMENT ON COLUMN audit.test_execution_log.passed IS
'Whether it passed.';
COMMENT ON COLUMN audit.test_execution_log.failure_reason IS
'Why it failed.';
COMMENT ON COLUMN audit.test_execution_log.duration_ms IS
'Execution latency in milliseconds.';
COMMENT ON COLUMN audit.test_execution_log.actual_output IS
'The output produced.';
COMMENT ON COLUMN audit.test_execution_log.created_at IS
'When run; the partition key.';
