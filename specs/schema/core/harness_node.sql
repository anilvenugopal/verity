-- core.harness_node  ·  subject: deploy  ·  (table)

-- A coordinator-eligible runtime HOST in a cluster: a pod in k8s, a VM on bare Linux.
-- Distinct from core.harness_instance (the running container/image). This is the unit
-- that can hold the coordinator lease. The spoke never writes Postgres (ADR-0003);
-- the Harness Gateway API maintains this table from registration + heartbeats.
CREATE TABLE core.harness_node (
    harness_node_id              uuid        NOT NULL DEFAULT uuidv7(),
    deployment_cluster_id        uuid        NOT NULL,
    node_identifier              text        NOT NULL,                  -- stable host id: pod name (k8s) or hostname/VM id (Linux)
    is_coordinator_eligible      boolean     NOT NULL DEFAULT true,
    is_coordinator_active        boolean     NOT NULL DEFAULT false,    -- mirror of who holds the lease (observability only)
    coordinator_lease_expires_at timestamptz,                           -- mirror of core.harness_coordinator for the portal
    harness_node_status_code     text        NOT NULL DEFAULT 'active', -- reference.harness_node_status
    runtime_version              text        NOT NULL,
    last_heartbeat_at            timestamptz,
    registered_at                timestamptz NOT NULL DEFAULT now(),
    deregistered_at              timestamptz,
    CONSTRAINT pk_harness_node PRIMARY KEY (harness_node_id),
    CONSTRAINT fk_harness_node_cluster FOREIGN KEY (deployment_cluster_id)
        REFERENCES core.deployment_cluster (deployment_cluster_id) ON DELETE RESTRICT,
    CONSTRAINT fk_harness_node_status FOREIGN KEY (harness_node_status_code)
        REFERENCES reference.harness_node_status (code),
    CONSTRAINT uq_harness_node_identifier UNIQUE (deployment_cluster_id, node_identifier));
COMMENT ON TABLE core.harness_node IS
'A coordinator-eligible runtime host in a cluster — a pod in k8s, a VM on bare Linux.
Distinct from core.harness_instance (the running container/image). This is the unit that
can hold the coordinator lease. Maintained hub-side from registration and heartbeats; the
spoke never writes Postgres.

@tier 1
@lifecycle mutable
@subject deploy
@status reference.harness_node_status
@invariant lease authority lives in harness_coordinator; columns here are an observability mirror
@adr 0010
@adr 0003';
COMMENT ON COLUMN core.harness_node.harness_node_id IS 'Surrogate key.';
COMMENT ON COLUMN core.harness_node.deployment_cluster_id IS 'Cluster this host belongs to. @ref core.deployment_cluster hard';
COMMENT ON COLUMN core.harness_node.node_identifier IS 'Stable host id: pod name (k8s) or hostname/VM id (Linux). Unique within the cluster.';
COMMENT ON COLUMN core.harness_node.is_coordinator_eligible IS 'Whether this host may stand for coordinator election. @default true';
COMMENT ON COLUMN core.harness_node.is_coordinator_active IS 'Mirror of "this host currently holds the lease" for the dashboard. @actor coordinator';
COMMENT ON COLUMN core.harness_node.coordinator_lease_expires_at IS 'Mirror of harness_coordinator.lease_expires_at for the portal. @actor coordinator @nullable-when never coordinator';
COMMENT ON COLUMN core.harness_node.harness_node_status_code IS 'Host lifecycle state. @status reference.harness_node_status';
COMMENT ON COLUMN core.harness_node.runtime_version IS 'Harness runtime version this host reports.';
COMMENT ON COLUMN core.harness_node.last_heartbeat_at IS 'Last heartbeat seen from this host. @actor coordinator';
COMMENT ON COLUMN core.harness_node.registered_at IS 'When the host first enrolled.';
COMMENT ON COLUMN core.harness_node.deregistered_at IS 'When the host left the fleet. @nullable-when still active';
CREATE INDEX ix_harness_node_cluster ON core.harness_node (deployment_cluster_id);
