-- core.test_case_mock  ·  subject: validation  ·  (table)

CREATE TABLE core.test_case_mock (
    test_case_mock_id uuid NOT NULL DEFAULT uuidv7(), test_case_id uuid NOT NULL,
    mock_kind_code text NOT NULL DEFAULT 'tool', mock_key text NOT NULL, call_order integer NOT NULL DEFAULT 1,
    mock_response jsonb NOT NULL, description text, created_at timestamptz NOT NULL DEFAULT now(),
    CONSTRAINT pk_test_case_mock PRIMARY KEY (test_case_mock_id),
    CONSTRAINT fk_test_case_mock_case FOREIGN KEY (test_case_id) REFERENCES core.test_case (test_case_id) ON DELETE CASCADE,
    CONSTRAINT fk_test_case_mock_kind FOREIGN KEY (mock_kind_code) REFERENCES reference.mock_kind (code),
    CONSTRAINT ck_test_case_mock_order CHECK (call_order >= 1));
COMMENT ON TABLE core.test_case_mock IS
'A mocked tool/MCP response for a test case, so the case runs deterministically without calling the real backend. Ordered by call_order when a case makes multiple calls to the same key (C9).

@tier 1
@lifecycle mutable
@subject validation
@status reference.mock_kind';
COMMENT ON COLUMN core.test_case_mock.test_case_mock_id IS
'Identity of the mock.';
COMMENT ON COLUMN core.test_case_mock.test_case_id IS
'The case this mock serves. @ref core.test_case hard';
COMMENT ON COLUMN core.test_case_mock.mock_kind_code IS
'What is mocked — tool/mcp/... @status reference.mock_kind';
COMMENT ON COLUMN core.test_case_mock.mock_key IS
'Which tool/MCP call this mocks.';
COMMENT ON COLUMN core.test_case_mock.call_order IS
'Order when the case calls the same key more than once. At least 1.';
COMMENT ON COLUMN core.test_case_mock.mock_response IS
'The canned response returned.';
COMMENT ON COLUMN core.test_case_mock.description IS
'Note on the mock.';
COMMENT ON COLUMN core.test_case_mock.created_at IS
'When created.';
