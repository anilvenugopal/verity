-- core.execution_run_status  ·  subject: runs  ·  (table)

CREATE TABLE core.execution_run_status (
    execution_run_status_id uuid      NOT NULL DEFAULT uuidv7(),
    execution_run_id        uuid      NOT NULL,
    run_status_code         text      NOT NULL,                  -- reference.run_status
    completion_status_code  text,                                  -- reference.run_completion_status; set on terminal 'released'
    worker_instance_id      uuid,                                  -- soft -> harness_instance (the executing container)
    worker_node_id          uuid,                                  -- soft -> harness_node (the host the worker ran on; B3)
    decision_log_id         uuid,                                  -- soft -> audit.decision_log (terminal)
    error_code              text,
    detail                  jsonb      NOT NULL DEFAULT '{}'::jsonb,
    created_at              timestamptz NOT NULL DEFAULT now(),
    CONSTRAINT pk_execution_run_status PRIMARY KEY (execution_run_status_id),
    CONSTRAINT fk_execution_run_status_run FOREIGN KEY (execution_run_id)
        REFERENCES core.execution_run (execution_run_id) ON DELETE RESTRICT,
    CONSTRAINT fk_execution_run_status_status FOREIGN KEY (run_status_code)
        REFERENCES reference.run_status (code),
    CONSTRAINT fk_execution_run_status_completion FOREIGN KEY (completion_status_code)
        REFERENCES reference.run_completion_status (code));
COMMENT ON TABLE core.execution_run_status IS
'The append-only event stream for a run''s lifecycle: one immutable row per transition
(submitted -> claimed -> heartbeat… -> released), reported by the cluster through the
Harness Gateway API and written in the same transaction as the harness_dispatch update so
operational state and audit can never diverge. Nothing updates a run''s state in place;
"current state" is the execution_run_current view over the latest row (D4, ADR-0010).

@tier 1
@lifecycle append-only
@subject runs
@leg cluster->hub
@status reference.run_status
@status reference.run_completion_status
@invariant written in the same transaction as harness_dispatch
@decision D4
@adr 0010';
COMMENT ON COLUMN core.execution_run_status.execution_run_status_id IS
'Identity of this state-transition event.';
COMMENT ON COLUMN core.execution_run_status.execution_run_id IS
'The run whose state changed; the sequence of this run''s rows is its full history. @ref core.execution_run hard';
COMMENT ON COLUMN core.execution_run_status.run_status_code IS
'The transition this row records — submitted/claimed/heartbeat/released. @status reference.run_status';
COMMENT ON COLUMN core.execution_run_status.completion_status_code IS
'Terminal outcome (complete/cancelled/errored), set only on the released event and null on every earlier transition. @status reference.run_completion_status';
COMMENT ON COLUMN core.execution_run_status.worker_instance_id IS
'The harness container that executed the run; soft ref because a Tier-1 run event must survive the ephemeral worker (HPA churn). @ref core.harness_instance soft';
COMMENT ON COLUMN core.execution_run_status.worker_node_id IS
'The host the worker ran on, kept for operational diagnostics (which node to investigate); set alongside worker_instance_id. @ref core.harness_node soft';
COMMENT ON COLUMN core.execution_run_status.decision_log_id IS
'Links the terminal event to the canonical decision record in the Tier-2 log; soft ref across the tier boundary. @ref audit.decision_log soft';
COMMENT ON COLUMN core.execution_run_status.error_code IS
'Failure category on an errored release; null otherwise.';
COMMENT ON COLUMN core.execution_run_status.detail IS
'Transition-specific payload — heartbeat metrics, claim metadata, or error detail.';
COMMENT ON COLUMN core.execution_run_status.created_at IS
'When the transition occurred; the ordering key that defines "latest state". @actor coordinator';
CREATE INDEX ix_execution_run_status_run_time ON core.execution_run_status (execution_run_id, created_at DESC);
