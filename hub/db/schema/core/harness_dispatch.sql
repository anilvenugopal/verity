-- core.harness_dispatch  ·  subject: runs  ·  (table)

-- Current operational dispatch state for ONE run within a cluster — the mutable
-- materialised row the coordinator polls (via the Harness Gateway API; the spoke holds
-- no DB credential, ADR-0003). The append-only audit of the same transitions lives in
-- core.execution_run_status; the two are written in ONE transaction. Columns name the
-- actor at each hop along hub -> cluster -> worker; status is reference.run_dispatch_status.
CREATE TABLE core.harness_dispatch (
    harness_dispatch_id        uuid        NOT NULL DEFAULT uuidv7(),
    execution_run_id           uuid        NOT NULL,
    deployment_cluster_id      uuid        NOT NULL,
    run_dispatch_status_code   text        NOT NULL DEFAULT 'queued', -- reference.run_dispatch_status
    priority                   smallint    NOT NULL DEFAULT 5,
    attempt_number             smallint    NOT NULL DEFAULT 1,
    max_attempts               smallint    NOT NULL DEFAULT 3,
    requeue_reason             text,
    -- actor-named lifecycle (who acts at each hop: hub -> cluster -> worker):
    enqueued_at                timestamptz NOT NULL DEFAULT now(),     -- hub
    published_to_cluster_at    timestamptz,                            -- relay -> NATS (hub -> cluster)
    claimed_by_coordinator_at  timestamptz,                            -- coordinator
    assigned_to_instance_id    uuid,                                   -- coordinator -> worker (soft -> harness_instance)
    assigned_to_node_id        uuid,                                   -- coordinator -> worker (soft -> harness_node)
    worker_started_at          timestamptz,                            -- worker
    worker_heartbeat_at        timestamptz,                            -- worker liveness (watchdog input)
    timeout_at                 timestamptz,                            -- worker deadline (watchdog requeues past this)
    released_at                timestamptz,                            -- worker (terminal)
    write_idempotency_key      text GENERATED ALWAYS AS
        (execution_run_id::text || '-a' || attempt_number::text) STORED, -- changes per requeue; target connectors dedupe on it
    failure_code               text,
    failure_detail             text,
    updated_at                 timestamptz NOT NULL DEFAULT now(),
    CONSTRAINT pk_harness_dispatch PRIMARY KEY (harness_dispatch_id),
    CONSTRAINT uq_harness_dispatch_run UNIQUE (execution_run_id),
    CONSTRAINT fk_harness_dispatch_run FOREIGN KEY (execution_run_id)
        REFERENCES core.execution_run (execution_run_id) ON DELETE RESTRICT,
    CONSTRAINT fk_harness_dispatch_cluster FOREIGN KEY (deployment_cluster_id)
        REFERENCES core.deployment_cluster (deployment_cluster_id) ON DELETE RESTRICT,
    CONSTRAINT fk_harness_dispatch_status FOREIGN KEY (run_dispatch_status_code)
        REFERENCES reference.run_dispatch_status (code));
-- coordinator polling: next queued jobs for my cluster by priority
CREATE INDEX ix_harness_dispatch_pollable ON core.harness_dispatch (deployment_cluster_id, priority, enqueued_at)
    WHERE run_dispatch_status_code IN ('queued','requeued');
-- watchdog: stale executing jobs past their deadline
CREATE INDEX ix_harness_dispatch_watchdog ON core.harness_dispatch (deployment_cluster_id, timeout_at)
    WHERE run_dispatch_status_code = 'executing';
-- worker load queries
CREATE INDEX ix_harness_dispatch_worker ON core.harness_dispatch (assigned_to_instance_id)
    WHERE run_dispatch_status_code = 'executing';
COMMENT ON TABLE core.harness_dispatch IS
'Current operational dispatch state for one run within a cluster — the mutable row the
coordinator polls to find work. Its append-only twin is execution_run_status; the two are
written in the same transaction so they cannot drift.

@tier 1
@lifecycle mutable
@subject runs
@leg hub->cluster->worker
@status reference.run_dispatch_status
@invariant written in the same transaction as execution_run_status
@invariant one row per execution_run (uq_harness_dispatch_run)
@adr 0010';
COMMENT ON COLUMN core.harness_dispatch.harness_dispatch_id IS 'Surrogate key.';
COMMENT ON COLUMN core.harness_dispatch.execution_run_id IS 'The run being dispatched. @ref core.execution_run hard';
COMMENT ON COLUMN core.harness_dispatch.deployment_cluster_id IS 'Cluster the run is dispatched to. @ref core.deployment_cluster hard';
COMMENT ON COLUMN core.harness_dispatch.run_dispatch_status_code IS 'Where the run is along hub->cluster->worker. @status reference.run_dispatch_status';
COMMENT ON COLUMN core.harness_dispatch.priority IS 'Dispatch order; lower value = sooner. @units rank @default 5';
COMMENT ON COLUMN core.harness_dispatch.attempt_number IS 'Current execution attempt; increments on requeue. @default 1';
COMMENT ON COLUMN core.harness_dispatch.max_attempts IS 'Requeue ceiling; past it the run fails with max_retries_exceeded. @default 3';
COMMENT ON COLUMN core.harness_dispatch.requeue_reason IS 'Why the most recent requeue happened (worker dead, timeout, …). @nullable-when never requeued';
COMMENT ON COLUMN core.harness_dispatch.enqueued_at IS 'When the hub enqueued the run. @actor hub';
COMMENT ON COLUMN core.harness_dispatch.published_to_cluster_at IS 'When verity-relay published it to the cluster NATS subject. @actor relay @leg hub->cluster';
COMMENT ON COLUMN core.harness_dispatch.claimed_by_coordinator_at IS 'When the elected coordinator claimed the run. @actor coordinator';
COMMENT ON COLUMN core.harness_dispatch.assigned_to_instance_id IS 'Worker container the coordinator handed the run to. @ref core.harness_instance soft @actor coordinator';
COMMENT ON COLUMN core.harness_dispatch.assigned_to_node_id IS 'Host the worker runs on. @ref core.harness_node soft @actor coordinator';
COMMENT ON COLUMN core.harness_dispatch.worker_started_at IS 'When the worker began executing. @actor worker';
COMMENT ON COLUMN core.harness_dispatch.worker_heartbeat_at IS 'Last worker liveness signal; watchdog input. @actor worker';
COMMENT ON COLUMN core.harness_dispatch.timeout_at IS 'Execution deadline; the watchdog requeues runs still executing past this. @actor coordinator';
COMMENT ON COLUMN core.harness_dispatch.released_at IS 'When the worker released the run (terminal). @actor worker';
COMMENT ON COLUMN core.harness_dispatch.write_idempotency_key IS 'run_id + attempt; changes on every requeue so target connectors dedupe writes after a re-execution. @values generated-stored';
COMMENT ON COLUMN core.harness_dispatch.failure_code IS 'Terminal failure category, if any. @nullable-when not failed';
COMMENT ON COLUMN core.harness_dispatch.failure_detail IS 'Human-readable failure context. @nullable-when not failed';
COMMENT ON COLUMN core.harness_dispatch.updated_at IS 'Last mutation of this row. @actor gateway';
