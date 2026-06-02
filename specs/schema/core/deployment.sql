-- core.deployment  ·  subject: deploy  ·  (table)

CREATE TABLE core.deployment (
    deployment_id         uuid       NOT NULL DEFAULT uuidv7(),
    package_id            uuid       NOT NULL,
    harness_image_id      uuid       NOT NULL,                  -- the EXACT pinned image (resolved at deploy)
    deployment_cluster_id uuid       NOT NULL,
    deployment_run_mode_code text    NOT NULL,                  -- live|shadow|ab|locked
    deployment_status_code text      NOT NULL DEFAULT 'active', -- active|superseded|stopped (mutable; transitions -> audit.status_transition)
    deployed_by_actor_id  uuid       NOT NULL,
    deployed_role_code    text       NOT NULL,
    created_at            timestamptz NOT NULL DEFAULT now(),
    updated_at            timestamptz NOT NULL DEFAULT now(),
    CONSTRAINT pk_deployment PRIMARY KEY (deployment_id),
    CONSTRAINT fk_deployment_package FOREIGN KEY (package_id) REFERENCES core.package (package_id) ON DELETE RESTRICT,
    CONSTRAINT fk_deployment_image FOREIGN KEY (harness_image_id) REFERENCES core.harness_image (harness_image_id) ON DELETE RESTRICT,
    CONSTRAINT fk_deployment_cluster FOREIGN KEY (deployment_cluster_id) REFERENCES core.deployment_cluster (deployment_cluster_id) ON DELETE RESTRICT,
    CONSTRAINT fk_deployment_run_mode FOREIGN KEY (deployment_run_mode_code) REFERENCES reference.deployment_run_mode (code),
    CONSTRAINT fk_deployment_status FOREIGN KEY (deployment_status_code) REFERENCES reference.deployment_status (code),
    CONSTRAINT fk_deployment_deployed_by FOREIGN KEY (deployed_by_actor_id) REFERENCES core.actor (actor_id),
    CONSTRAINT fk_deployment_deployed_role FOREIGN KEY (deployed_role_code) REFERENCES reference.role (code));
COMMENT ON TABLE core.deployment IS 'tier:1. A package placed to run: pinned harness image (both package & image digests recorded), cluster, run_mode, status. champion!=deployed. D8/ADR-0006.';
CREATE INDEX ix_deployment_package ON core.deployment (package_id);
CREATE INDEX ix_deployment_cluster ON core.deployment (deployment_cluster_id);
