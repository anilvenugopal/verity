-- core.validation_record_result  ·  subject: validation  ·  (table)

CREATE TABLE core.validation_record_result (
    validation_record_result_id uuid NOT NULL DEFAULT uuidv7(), validation_run_id uuid NOT NULL,
    ground_truth_record_id uuid NOT NULL, validation_match_type_code text NOT NULL, passed boolean NOT NULL,
    score numeric(6,4), detail jsonb, created_at timestamptz NOT NULL DEFAULT now(),
    CONSTRAINT pk_validation_record_result PRIMARY KEY (validation_record_result_id),
    CONSTRAINT fk_vrr_run FOREIGN KEY (validation_run_id) REFERENCES core.validation_run (validation_run_id) ON DELETE CASCADE,
    CONSTRAINT fk_vrr_record FOREIGN KEY (ground_truth_record_id) REFERENCES core.ground_truth_record (ground_truth_record_id) ON DELETE RESTRICT,
    CONSTRAINT fk_vrr_match FOREIGN KEY (validation_match_type_code) REFERENCES reference.validation_match_type (code));
