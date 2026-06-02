-- core.execution_run_status  ·  subject: runs  ·  (table)

CREATE TABLE core.execution_run_status (
    execution_run_status_id uuid      NOT NULL DEFAULT uuidv7(),
    execution_run_id        uuid      NOT NULL,
    run_status              core.run_status NOT NULL,
    completion_status       core.run_completion_status,        -- set on the terminal 'released' event
    worker_instance_id      uuid,                                  -- soft -> harness_instance (08)
    decision_log_id         uuid,                                  -- soft -> audit.decision_log (terminal)
    error_code              text,
    detail                  jsonb      NOT NULL DEFAULT '{}'::jsonb,
    created_at              timestamptz NOT NULL DEFAULT now(),
    CONSTRAINT pk_execution_run_status PRIMARY KEY (execution_run_status_id),
    CONSTRAINT fk_execution_run_status_run FOREIGN KEY (execution_run_id)
        REFERENCES core.execution_run (execution_run_id) ON DELETE RESTRICT);
COMMENT ON TABLE core.execution_run_status IS 'tier:1 append-only. One row per run state transition (submitted/claimed/heartbeat/released). Current state via execution_run_current. Generalized v1 event-sourced model. D4.';
CREATE INDEX ix_execution_run_status_run_time ON core.execution_run_status (execution_run_id, created_at DESC);
