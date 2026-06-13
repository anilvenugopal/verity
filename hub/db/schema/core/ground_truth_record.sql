-- core.ground_truth_record  ·  subject: validation  ·  (table)

CREATE TABLE core.ground_truth_record (
    ground_truth_record_id uuid NOT NULL DEFAULT uuidv7(), ground_truth_dataset_id uuid NOT NULL,
    input_data jsonb NOT NULL, expected_output jsonb NOT NULL, created_at timestamptz NOT NULL DEFAULT now(),
    CONSTRAINT pk_ground_truth_record PRIMARY KEY (ground_truth_record_id),
    CONSTRAINT fk_gtr_dataset FOREIGN KEY (ground_truth_dataset_id) REFERENCES core.ground_truth_dataset (ground_truth_dataset_id) ON DELETE CASCADE);
CREATE INDEX ix_ground_truth_record_dataset ON core.ground_truth_record (ground_truth_dataset_id);
COMMENT ON TABLE core.ground_truth_record IS
'One labeled example in a ground-truth dataset: an input and its expected output, graded against during validation (C9).

@tier 1
@lifecycle mutable
@subject validation';
COMMENT ON COLUMN core.ground_truth_record.ground_truth_record_id IS
'Identity of the record.';
COMMENT ON COLUMN core.ground_truth_record.ground_truth_dataset_id IS
'The dataset it belongs to. @ref core.ground_truth_dataset hard';
COMMENT ON COLUMN core.ground_truth_record.input_data IS
'The example input.';
COMMENT ON COLUMN core.ground_truth_record.expected_output IS
'The labeled expected output.';
COMMENT ON COLUMN core.ground_truth_record.created_at IS
'When created.';
