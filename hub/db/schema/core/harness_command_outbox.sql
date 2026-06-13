-- core.harness_command_outbox  ·  subject: deploy  ·  (table)

-- Transactional outbox for hub -> coordinator command delivery, written in ONE txn with
-- the core.harness_instance_command insert. verity-relay publishes to NATS
-- verity.cluster.{id}.commands; the coordinator ACKs via the Harness Gateway API.
-- Separate from core.run_dispatch_outbox because commands and runs differ in routing
-- (a specific cluster vs a run), TTL (commands expire), and ack semantics.
CREATE TABLE core.harness_command_outbox (
    harness_command_outbox_id    uuid        NOT NULL DEFAULT uuidv7(),
    harness_instance_command_id  uuid        NOT NULL,
    deployment_cluster_id        uuid        NOT NULL,
    subject                      text        NOT NULL,                  -- NATS subject (e.g. verity.cluster.{id}.commands)
    payload                      jsonb       NOT NULL,
    command_outbox_status_code   text        NOT NULL DEFAULT 'pending', -- reference.command_outbox_status
    published_to_cluster_at      timestamptz,                           -- relay -> NATS (hub -> cluster)
    acknowledged_at              timestamptz,                           -- coordinator executed + ACKed
    expires_at                   timestamptz NOT NULL DEFAULT now() + interval '24 hours',
    created_at                   timestamptz NOT NULL DEFAULT now(),    -- hub enqueue
    CONSTRAINT pk_harness_command_outbox PRIMARY KEY (harness_command_outbox_id),
    CONSTRAINT uq_hco_command UNIQUE (harness_instance_command_id),
    CONSTRAINT fk_hco_command FOREIGN KEY (harness_instance_command_id)
        REFERENCES core.harness_instance_command (harness_instance_command_id) ON DELETE RESTRICT,
    CONSTRAINT fk_hco_cluster FOREIGN KEY (deployment_cluster_id)
        REFERENCES core.deployment_cluster (deployment_cluster_id) ON DELETE RESTRICT,
    CONSTRAINT fk_hco_status FOREIGN KEY (command_outbox_status_code)
        REFERENCES reference.command_outbox_status (code));
CREATE INDEX ix_hco_unpublished ON core.harness_command_outbox (deployment_cluster_id, created_at)
    WHERE command_outbox_status_code IN ('pending','published');
COMMENT ON TABLE core.harness_command_outbox IS
'Transactional outbox for hub->coordinator command delivery, written in the same
transaction as the core.harness_instance_command insert. verity-relay publishes to NATS
verity.cluster.{id}.commands; the coordinator acks via the Harness Gateway API. Separate
from run_dispatch_outbox because commands route to a cluster (not a run), carry a TTL, and
ack rather than claim.

@tier 1
@lifecycle mutable
@subject deploy
@leg hub->cluster
@status reference.command_outbox_status
@invariant written in the same transaction as harness_instance_command
@adr 0010';
COMMENT ON COLUMN core.harness_command_outbox.harness_command_outbox_id IS 'Surrogate key.';
COMMENT ON COLUMN core.harness_command_outbox.harness_instance_command_id IS 'The command being delivered (one outbox row per command). @ref core.harness_instance_command hard';
COMMENT ON COLUMN core.harness_command_outbox.deployment_cluster_id IS 'Cluster the command targets. @ref core.deployment_cluster hard';
COMMENT ON COLUMN core.harness_command_outbox.subject IS 'NATS subject it is published to, e.g. verity.cluster.{id}.commands.';
COMMENT ON COLUMN core.harness_command_outbox.payload IS 'Command payload published to the coordinator.';
COMMENT ON COLUMN core.harness_command_outbox.command_outbox_status_code IS 'Delivery state (adds acknowledged/expired vs the run outbox). @status reference.command_outbox_status';
COMMENT ON COLUMN core.harness_command_outbox.published_to_cluster_at IS 'When verity-relay published it. @actor relay @leg hub->cluster';
COMMENT ON COLUMN core.harness_command_outbox.acknowledged_at IS 'When the coordinator executed and acked it. @actor coordinator @nullable-when not yet acked';
COMMENT ON COLUMN core.harness_command_outbox.expires_at IS 'TTL after which an undelivered command is swept to expired. @default now()+24h';
COMMENT ON COLUMN core.harness_command_outbox.created_at IS 'When the hub enqueued the command. @actor hub';
