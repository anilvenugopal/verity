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
COMMENT ON TABLE core.harness_instance IS 'tier:1. A running harness container on a cluster (the "collector"): current/desired image (patch via convergence), owned/shared scope, status, last_seen. D8.';
CREATE INDEX ix_harness_instance_cluster ON core.harness_instance (deployment_cluster_id);
