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
