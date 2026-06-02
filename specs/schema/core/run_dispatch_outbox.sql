-- core.run_dispatch_outbox  ·  subject: runs  ·  (table)

CREATE TABLE core.run_dispatch_outbox (
    run_dispatch_outbox_id uuid       NOT NULL DEFAULT uuidv7(),
    execution_run_id       uuid       NOT NULL,
    outbox_status          core.outbox_status NOT NULL DEFAULT 'pending',
    subject                text       NOT NULL,                   -- NATS subject (e.g. verity.runs.pending)
    payload                jsonb      NOT NULL,
    published_at           timestamptz,
    claimed_at             timestamptz,
    created_at             timestamptz NOT NULL DEFAULT now(),
    CONSTRAINT pk_run_dispatch_outbox PRIMARY KEY (run_dispatch_outbox_id),
    CONSTRAINT fk_run_dispatch_outbox_run FOREIGN KEY (execution_run_id)
        REFERENCES core.execution_run (execution_run_id) ON DELETE RESTRICT);
COMMENT ON TABLE core.run_dispatch_outbox IS 'tier:1. Transactional outbox: run insert + outbox row in one txn; verity-relay publishes to NATS and marks published_at (PCR §3.3).';
CREATE INDEX ix_run_dispatch_outbox_unpublished ON core.run_dispatch_outbox (created_at) WHERE outbox_status = 'pending';
