-- core.validation_run  ·  subject: validation  ·  (table)

CREATE TABLE core.validation_run (
    validation_run_id uuid NOT NULL DEFAULT uuidv7(), executable_version_id uuid NOT NULL,
    ground_truth_dataset_id uuid NOT NULL, validation_run_status_code text NOT NULL DEFAULT 'running',
    summary jsonb, started_at timestamptz NOT NULL DEFAULT now(), finished_at timestamptz,
    requested_by_actor_id uuid NOT NULL, requested_role_code text NOT NULL,
    CONSTRAINT pk_validation_run PRIMARY KEY (validation_run_id),
    CONSTRAINT fk_validation_run_version FOREIGN KEY (executable_version_id) REFERENCES core.executable_version (executable_version_id) ON DELETE RESTRICT,
    CONSTRAINT fk_validation_run_dataset FOREIGN KEY (ground_truth_dataset_id) REFERENCES core.ground_truth_dataset (ground_truth_dataset_id) ON DELETE RESTRICT,
    CONSTRAINT fk_validation_run_status FOREIGN KEY (validation_run_status_code) REFERENCES reference.validation_run_status (code),
    CONSTRAINT fk_validation_run_requested_by FOREIGN KEY (requested_by_actor_id) REFERENCES core.actor (actor_id),
    CONSTRAINT fk_validation_run_requested_role FOREIGN KEY (requested_role_code) REFERENCES reference.role (code));
COMMENT ON TABLE core.validation_run IS
'A run that grades an executable_version against a ground-truth dataset, producing per-record results and a summary. status is mutable through the run (C9).

@tier 1
@lifecycle mutable
@subject validation
@status reference.validation_run_status';
COMMENT ON COLUMN core.validation_run.validation_run_id IS
'Identity of the run.';
COMMENT ON COLUMN core.validation_run.executable_version_id IS
'The version being validated. @ref core.executable_version hard';
COMMENT ON COLUMN core.validation_run.ground_truth_dataset_id IS
'The dataset graded against. @ref core.ground_truth_dataset hard';
COMMENT ON COLUMN core.validation_run.validation_run_status_code IS
'Mutable run status (running/...). @status reference.validation_run_status';
COMMENT ON COLUMN core.validation_run.summary IS
'Aggregate results.';
COMMENT ON COLUMN core.validation_run.started_at IS
'When the run started.';
COMMENT ON COLUMN core.validation_run.finished_at IS
'When the run finished.';
COMMENT ON COLUMN core.validation_run.requested_by_actor_id IS
'Who requested it. @ref core.actor hard';
COMMENT ON COLUMN core.validation_run.requested_role_code IS
'The capacity they acted in. @status reference.role';
