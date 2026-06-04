-- core.harness_instance  ·  subject: deploy  ·  (table)

CREATE TABLE core.harness_instance (
    harness_instance_id   uuid       NOT NULL DEFAULT uuidv7(),
    deployment_cluster_id uuid       NOT NULL,
    current_image_id      uuid       NOT NULL,                  -- the image it is running
    desired_image_id      uuid,                                  -- patch target (desired-vs-current convergence)
    application_id        uuid,                                  -- owned (set) vs shared (NULL) fleet
    harness_instance_status_code text NOT NULL DEFAULT 'active',-- active | draining | disabled
    last_seen             timestamptz,                           -- denormalized from heartbeats (fast "who is down")
    registered_at         timestamptz NOT NULL DEFAULT now(),
    CONSTRAINT pk_harness_instance PRIMARY KEY (harness_instance_id),
    CONSTRAINT fk_harness_instance_cluster FOREIGN KEY (deployment_cluster_id) REFERENCES core.deployment_cluster (deployment_cluster_id) ON DELETE RESTRICT,
    CONSTRAINT fk_harness_instance_current_image FOREIGN KEY (current_image_id) REFERENCES core.harness_image (harness_image_id) ON DELETE RESTRICT,
    CONSTRAINT fk_harness_instance_desired_image FOREIGN KEY (desired_image_id) REFERENCES core.harness_image (harness_image_id) ON DELETE RESTRICT,
    CONSTRAINT fk_harness_instance_application FOREIGN KEY (application_id) REFERENCES core.application (application_id) ON DELETE RESTRICT,
    CONSTRAINT fk_harness_instance_status FOREIGN KEY (harness_instance_status_code) REFERENCES reference.harness_instance_status (code));
COMMENT ON TABLE core.harness_instance IS
'A running harness container on a cluster (a worker/collector). Tracks the image it is actually running versus the image the portal wants — that desired-vs-current gap is the patch signal — whether it is owned by one application or part of the shared fleet, and a denormalized last_seen so "who is down" is a single-row read rather than a scan of the Tier-2 heartbeat stream (D8, ADR-0010).

@tier 1
@lifecycle mutable
@subject deploy
@status reference.harness_instance_status
@decision D8
@adr 0010';
CREATE INDEX ix_harness_instance_cluster ON core.harness_instance (deployment_cluster_id);
COMMENT ON COLUMN core.harness_instance.harness_instance_id IS
'Identity of the running container.';
COMMENT ON COLUMN core.harness_instance.deployment_cluster_id IS
'The cluster it runs in. @ref core.deployment_cluster hard';
COMMENT ON COLUMN core.harness_instance.current_image_id IS
'The harness image it is actually running, as reported by the agent. @ref core.harness_image hard';
COMMENT ON COLUMN core.harness_instance.desired_image_id IS
'The image the portal wants it on; when it differs from current_image_id the gap is the patch signal for an image deployment (ADR-0010). @ref core.harness_image hard';
COMMENT ON COLUMN core.harness_instance.application_id IS
'Set for an application-owned instance; null for a shared-fleet instance serving several applications. @ref core.application hard';
COMMENT ON COLUMN core.harness_instance.harness_instance_status_code IS
'active/draining/disabled — the operational state the portal drives via commands. @status reference.harness_instance_status';
COMMENT ON COLUMN core.harness_instance.last_seen IS
'Denormalized from heartbeats so liveness is a single-row read, not a scan of the Tier-2 heartbeat partitions.';
COMMENT ON COLUMN core.harness_instance.registered_at IS
'When the instance first enrolled.';
