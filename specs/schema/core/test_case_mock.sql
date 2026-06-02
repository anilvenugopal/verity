-- core.test_case_mock  ·  subject: validation  ·  (table)

CREATE TABLE core.test_case_mock (
    test_case_mock_id uuid NOT NULL DEFAULT uuidv7(), test_case_id uuid NOT NULL,
    mock_kind_code text NOT NULL DEFAULT 'tool', mock_key text NOT NULL, call_order integer NOT NULL DEFAULT 1,
    mock_response jsonb NOT NULL, description text, created_at timestamptz NOT NULL DEFAULT now(),
    CONSTRAINT pk_test_case_mock PRIMARY KEY (test_case_mock_id),
    CONSTRAINT fk_test_case_mock_case FOREIGN KEY (test_case_id) REFERENCES core.test_case (test_case_id) ON DELETE CASCADE,
    CONSTRAINT fk_test_case_mock_kind FOREIGN KEY (mock_kind_code) REFERENCES reference.mock_kind (code),
    CONSTRAINT ck_test_case_mock_order CHECK (call_order >= 1));
