-- core.evaluation_run  ·  subject: validation  ·  (table)

CREATE TABLE core.evaluation_run (
    evaluation_run_id uuid NOT NULL DEFAULT uuidv7(), executable_version_id uuid NOT NULL,
    evaluation_type_code text NOT NULL, summary jsonb, created_at timestamptz NOT NULL DEFAULT now(),
    requested_by_actor_id uuid NOT NULL, requested_role_code text NOT NULL,
    CONSTRAINT pk_evaluation_run PRIMARY KEY (evaluation_run_id),
    CONSTRAINT fk_evaluation_run_version FOREIGN KEY (executable_version_id) REFERENCES core.executable_version (executable_version_id) ON DELETE RESTRICT,
    CONSTRAINT fk_evaluation_run_type FOREIGN KEY (evaluation_type_code) REFERENCES reference.evaluation_type (code),
    CONSTRAINT fk_evaluation_run_requested_by FOREIGN KEY (requested_by_actor_id) REFERENCES core.actor (actor_id),
    CONSTRAINT fk_evaluation_run_requested_role FOREIGN KEY (requested_role_code) REFERENCES reference.role (code));
COMMENT ON TABLE core.evaluation_run IS
'An evaluation of an executable_version of a given type (e.g. benchmark, red-team), with a summary. Distinct from validation_run, which grades against ground truth (C9).

@tier 1
@lifecycle mutable
@subject validation
@status reference.evaluation_type';
COMMENT ON COLUMN core.evaluation_run.evaluation_run_id IS
'Identity of the evaluation.';
COMMENT ON COLUMN core.evaluation_run.executable_version_id IS
'The version evaluated. @ref core.executable_version hard';
COMMENT ON COLUMN core.evaluation_run.evaluation_type_code IS
'The kind of evaluation. @status reference.evaluation_type';
COMMENT ON COLUMN core.evaluation_run.summary IS
'Evaluation results.';
COMMENT ON COLUMN core.evaluation_run.created_at IS
'When run.';
COMMENT ON COLUMN core.evaluation_run.requested_by_actor_id IS
'Who requested it. @ref core.actor hard';
COMMENT ON COLUMN core.evaluation_run.requested_role_code IS
'The capacity they acted in. @status reference.role';
