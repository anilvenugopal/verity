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
