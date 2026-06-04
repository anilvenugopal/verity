-- core.run_dispatch_outbox  ·  subject: runs  ·  (table)

CREATE TABLE core.run_dispatch_outbox (
    run_dispatch_outbox_id uuid       NOT NULL DEFAULT uuidv7(),
    execution_run_id       uuid       NOT NULL,
    outbox_status_code     text       NOT NULL DEFAULT 'pending', -- reference.outbox_status
    subject                text       NOT NULL,                   -- NATS subject (e.g. verity.runs.pending)
    payload                jsonb      NOT NULL,
    published_to_cluster_at timestamptz,                          -- relay -> NATS (hub -> cluster)
    claimed_at             timestamptz,                           -- coordinator claimed the published run
    created_at             timestamptz NOT NULL DEFAULT now(),    -- hub enqueue
    CONSTRAINT pk_run_dispatch_outbox PRIMARY KEY (run_dispatch_outbox_id),
    CONSTRAINT fk_run_dispatch_outbox_run FOREIGN KEY (execution_run_id)
        REFERENCES core.execution_run (execution_run_id) ON DELETE RESTRICT,
    CONSTRAINT fk_run_dispatch_outbox_status FOREIGN KEY (outbox_status_code)
        REFERENCES reference.outbox_status (code));
COMMENT ON TABLE core.run_dispatch_outbox IS
'The transactional outbox that bridges a committed run to the NATS dispatch bus without a
dual-write. Governance inserts the execution_run and this row in one transaction; the
verity-relay service then reads unpublished rows (SKIP LOCKED), publishes to NATS, and
marks them published — so a run can never be committed-but-undispatched or
dispatched-but-uncommitted. The verity-dispatch-sweep re-publishes rows stuck unclaimed.
The coordinator never reads this table; it consumes from NATS (PCR §3.3, ADR-0010).

@tier 1
@lifecycle mutable
@subject runs
@leg hub->cluster
@status reference.outbox_status
@invariant inserted in the same transaction as execution_run (no dual-write)
@adr 0010';
COMMENT ON COLUMN core.run_dispatch_outbox.run_dispatch_outbox_id IS
'Identity of the outbox entry.';
COMMENT ON COLUMN core.run_dispatch_outbox.execution_run_id IS
'The run awaiting dispatch. One outbox row per run hand-off to the bus. @ref core.execution_run hard';
COMMENT ON COLUMN core.run_dispatch_outbox.outbox_status_code IS
'Where this row is in the Postgres->NATS hand-off: pending -> published -> claimed (or failed). Drives the relay poll and the sweep. @status reference.outbox_status';
COMMENT ON COLUMN core.run_dispatch_outbox.subject IS
'The NATS subject the relay publishes to, e.g. verity.runs.pending; the cluster''s coordinator is subscribed to it.';
COMMENT ON COLUMN core.run_dispatch_outbox.payload IS
'The dispatch message the relay publishes (everything the coordinator needs to claim the run via the gateway).';
COMMENT ON COLUMN core.run_dispatch_outbox.published_to_cluster_at IS
'When verity-relay published the row to NATS; the moment ownership of progress passes from the outbox to the bus. @actor relay @leg hub->cluster';
COMMENT ON COLUMN core.run_dispatch_outbox.claimed_at IS
'When a coordinator claimed the published run (via the gateway); the sweep ignores rows past this. @actor coordinator';
COMMENT ON COLUMN core.run_dispatch_outbox.created_at IS
'When governance enqueued the row — set in the same transaction as the run insert. @actor hub';
CREATE INDEX ix_run_dispatch_outbox_unpublished ON core.run_dispatch_outbox (created_at) WHERE outbox_status_code = 'pending';
