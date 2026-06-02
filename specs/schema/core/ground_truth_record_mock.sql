-- core.ground_truth_record_mock  ·  subject: validation  ·  (table)

CREATE TABLE core.ground_truth_record_mock (
    ground_truth_record_mock_id uuid NOT NULL DEFAULT uuidv7(), ground_truth_record_id uuid NOT NULL,
    mock_kind_code text NOT NULL DEFAULT 'tool', mock_key text NOT NULL, mock_response jsonb NOT NULL,
    CONSTRAINT pk_ground_truth_record_mock PRIMARY KEY (ground_truth_record_mock_id),
    CONSTRAINT fk_gtrm_record FOREIGN KEY (ground_truth_record_id) REFERENCES core.ground_truth_record (ground_truth_record_id) ON DELETE CASCADE,
    CONSTRAINT fk_gtrm_kind FOREIGN KEY (mock_kind_code) REFERENCES reference.mock_kind (code));
