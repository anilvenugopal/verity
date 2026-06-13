-- core.ground_truth_record_mock  ·  subject: validation  ·  (table)

CREATE TABLE core.ground_truth_record_mock (
    ground_truth_record_mock_id uuid NOT NULL DEFAULT uuidv7(), ground_truth_record_id uuid NOT NULL,
    mock_kind_code text NOT NULL DEFAULT 'tool', mock_key text NOT NULL, mock_response jsonb NOT NULL,
    CONSTRAINT pk_ground_truth_record_mock PRIMARY KEY (ground_truth_record_mock_id),
    CONSTRAINT fk_gtrm_record FOREIGN KEY (ground_truth_record_id) REFERENCES core.ground_truth_record (ground_truth_record_id) ON DELETE CASCADE,
    CONSTRAINT fk_gtrm_kind FOREIGN KEY (mock_kind_code) REFERENCES reference.mock_kind (code));
COMMENT ON TABLE core.ground_truth_record_mock IS
'A mocked tool/MCP response for a ground-truth record, so validation replays the record deterministically (C9).

@tier 1
@lifecycle mutable
@subject validation
@status reference.mock_kind';
COMMENT ON COLUMN core.ground_truth_record_mock.ground_truth_record_mock_id IS
'Identity of the mock.';
COMMENT ON COLUMN core.ground_truth_record_mock.ground_truth_record_id IS
'The record this mock serves. @ref core.ground_truth_record hard';
COMMENT ON COLUMN core.ground_truth_record_mock.mock_kind_code IS
'What is mocked. @status reference.mock_kind';
COMMENT ON COLUMN core.ground_truth_record_mock.mock_key IS
'Which call this mocks.';
COMMENT ON COLUMN core.ground_truth_record_mock.mock_response IS
'The canned response.';
