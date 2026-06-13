-- core.harness_coordinator  ·  subject: deploy  ·  (table)

-- The coordinator (master) lease: one row per cluster naming the node that currently
-- leads job dispatch. The spoke NEVER writes this directly (ADR-0003 API-only); the
-- Harness Gateway API performs the atomic refresh/steal on every coordinator heartbeat:
--     UPDATE core.harness_coordinator
--        SET coordinator_node_id = $node, last_heartbeat_at = now(),
--            lease_expires_at = now() + lease_duration
--      WHERE deployment_cluster_id = $cluster
--        AND (coordinator_node_id = $node OR lease_expires_at < now());
-- and returns lease_held = (row_count > 0). That single atomic statement IS the leader
-- election: two standbys cannot both win (row lock serialises them) — no split-brain,
-- no advisory locks, no NATS KV. lease_duration = 3x heartbeat_interval (6 min default).
CREATE TABLE core.harness_coordinator (
    deployment_cluster_id   uuid        NOT NULL,
    coordinator_node_id     uuid        NOT NULL,                  -- soft -> harness_node (the lease holder)
    claimed_at              timestamptz NOT NULL DEFAULT now(),
    last_heartbeat_at       timestamptz NOT NULL DEFAULT now(),
    lease_expires_at        timestamptz NOT NULL,
    CONSTRAINT pk_harness_coordinator PRIMARY KEY (deployment_cluster_id),
    CONSTRAINT fk_harness_coordinator_cluster FOREIGN KEY (deployment_cluster_id)
        REFERENCES core.deployment_cluster (deployment_cluster_id) ON DELETE RESTRICT);
COMMENT ON TABLE core.harness_coordinator IS
'The coordinator (master) lease: one row per cluster naming the node that currently leads
job dispatch. The spoke never writes this; the Harness Gateway API performs the atomic
refresh/steal on each coordinator heartbeat (UPDATE ... WHERE lease_expires_at < now()).
That single atomic statement IS the leader election — row locking serialises competitors,
so split-brain is impossible. No advisory locks, no NATS KV.

@tier 1
@lifecycle mutable
@subject deploy
@leg within-cluster leadership, arbitrated hub-side
@invariant election = atomic conditional UPDATE; lease = 3x heartbeat (6 min default)
@adr 0010
@adr 0003';
COMMENT ON COLUMN core.harness_coordinator.deployment_cluster_id IS 'Cluster this lease governs (one lease per cluster). @ref core.deployment_cluster hard';
COMMENT ON COLUMN core.harness_coordinator.coordinator_node_id IS 'Host currently holding the lease. @ref core.harness_node soft';
COMMENT ON COLUMN core.harness_coordinator.claimed_at IS 'When the current holder first won the lease.';
COMMENT ON COLUMN core.harness_coordinator.last_heartbeat_at IS 'Last lease refresh. @actor coordinator';
COMMENT ON COLUMN core.harness_coordinator.lease_expires_at IS 'Lease deadline; a standby may steal once now() passes it. @actor coordinator';
