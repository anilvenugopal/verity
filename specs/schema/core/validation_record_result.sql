-- core.validation_record_result  ·  subject: validation  ·  (table)

CREATE TABLE core.validation_record_result (
    validation_record_result_id uuid NOT NULL DEFAULT uuidv7(), validation_run_id uuid NOT NULL,
    ground_truth_record_id uuid NOT NULL, validation_match_type_code text NOT NULL, passed boolean NOT NULL,
    score numeric(6,4), detail jsonb, created_at timestamptz NOT NULL DEFAULT now(),
    CONSTRAINT pk_validation_record_result PRIMARY KEY (validation_record_result_id),
    CONSTRAINT fk_vrr_run FOREIGN KEY (validation_run_id) REFERENCES core.validation_run (validation_run_id) ON DELETE CASCADE,
    CONSTRAINT fk_vrr_record FOREIGN KEY (ground_truth_record_id) REFERENCES core.ground_truth_record (ground_truth_record_id) ON DELETE RESTRICT,
    CONSTRAINT fk_vrr_match FOREIGN KEY (validation_match_type_code) REFERENCES reference.validation_match_type (code));
COMMENT ON TABLE core.validation_record_result IS
'The per-record outcome of a validation run: whether the version''s output matched the ground-truth record, by which match type, with a score and detail (C9).

@tier 1
@lifecycle insert-only
@subject validation
@status reference.validation_match_type';
COMMENT ON COLUMN core.validation_record_result.validation_record_result_id IS
'Identity of the result.';
COMMENT ON COLUMN core.validation_record_result.validation_run_id IS
'The run this result is part of. @ref core.validation_run hard';
COMMENT ON COLUMN core.validation_record_result.ground_truth_record_id IS
'The record graded. @ref core.ground_truth_record hard';
COMMENT ON COLUMN core.validation_record_result.validation_match_type_code IS
'How the match was judged. @status reference.validation_match_type';
COMMENT ON COLUMN core.validation_record_result.passed IS
'Whether the record passed.';
COMMENT ON COLUMN core.validation_record_result.score IS
'Match score.';
COMMENT ON COLUMN core.validation_record_result.detail IS
'Per-record detail.';
COMMENT ON COLUMN core.validation_record_result.created_at IS
'When recorded.';
