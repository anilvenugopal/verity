-- core.deployment_cluster  ·  subject: deploy  ·  (table)

CREATE TABLE core.deployment_cluster (
    deployment_cluster_id uuid       NOT NULL DEFAULT uuidv7(),
    deployment_environment_id uuid   NOT NULL,
    name                  text       NOT NULL,
    created_at            timestamptz NOT NULL DEFAULT now(),
    CONSTRAINT pk_deployment_cluster PRIMARY KEY (deployment_cluster_id),
    CONSTRAINT fk_deployment_cluster_environment FOREIGN KEY (deployment_environment_id) REFERENCES core.deployment_environment (deployment_environment_id) ON DELETE RESTRICT,
    CONSTRAINT uq_deployment_cluster_name UNIQUE (name));
COMMENT ON TABLE core.deployment_cluster IS 'tier:1. A cluster within an environment (multiple per env, incl. ephemeral/replay). D8.';
