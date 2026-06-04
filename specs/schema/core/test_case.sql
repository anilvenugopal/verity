-- core.test_case  ·  subject: validation  ·  (table)

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
COMMENT ON TABLE core.test_case IS
'A single test case in a suite: input, expected output, the metric used to grade it, and which versions it applies to. May be flagged adversarial. Mocks for its tool/MCP calls live in test_case_mock so the case runs deterministically (C9).

@tier 1
@lifecycle mutable
@subject validation
@status reference.metric_type';
COMMENT ON COLUMN core.test_case.test_case_id IS
'Identity of the case.';
COMMENT ON COLUMN core.test_case.test_suite_id IS
'The suite this belongs to. @ref core.test_suite hard';
COMMENT ON COLUMN core.test_case.name IS
'Case name.';
COMMENT ON COLUMN core.test_case.description IS
'What the case checks.';
COMMENT ON COLUMN core.test_case.input_data IS
'The case input.';
COMMENT ON COLUMN core.test_case.expected_output IS
'The expected output to grade against.';
COMMENT ON COLUMN core.test_case.metric_type_code IS
'How the result is graded. @status reference.metric_type';
COMMENT ON COLUMN core.test_case.metric_config IS
'Metric-specific configuration.';
COMMENT ON COLUMN core.test_case.applies_to_versions IS
'Version ids this case applies to; empty = all.';
COMMENT ON COLUMN core.test_case.is_adversarial IS
'Whether this is an adversarial/red-team case.';
COMMENT ON COLUMN core.test_case.tags IS
'Free-form tags.';
COMMENT ON COLUMN core.test_case.active IS
'Whether the case is in use.';
COMMENT ON COLUMN core.test_case.created_at IS
'When created.';
