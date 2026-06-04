-- core.deployment_cluster  ·  subject: deploy  ·  (table)

CREATE TABLE core.deployment_cluster (
    deployment_cluster_id uuid       NOT NULL DEFAULT uuidv7(),
    deployment_environment_id uuid   NOT NULL,
    name                  text       NOT NULL,
    created_at            timestamptz NOT NULL DEFAULT now(),
    CONSTRAINT pk_deployment_cluster PRIMARY KEY (deployment_cluster_id),
    CONSTRAINT fk_deployment_cluster_environment FOREIGN KEY (deployment_environment_id) REFERENCES core.deployment_environment (deployment_environment_id) ON DELETE RESTRICT,
    CONSTRAINT uq_deployment_cluster_name UNIQUE (name));
COMMENT ON TABLE core.deployment_cluster IS
'A cluster within an environment — the unit a harness pool runs on and that runs and dispatch are scoped to. An environment can hold many, including ephemeral clusters spun up for reproducible replay (D8, ADR-0010).

@tier 1
@lifecycle mutable
@subject deploy
@decision D8
@adr 0010';
COMMENT ON COLUMN core.deployment_cluster.deployment_cluster_id IS
'Identity of the cluster; runs, dispatch, the coordinator lease, and credentials are all scoped to it.';
COMMENT ON COLUMN core.deployment_cluster.deployment_environment_id IS
'The environment this cluster belongs to. @ref core.deployment_environment hard';
COMMENT ON COLUMN core.deployment_cluster.name IS
'Human name of the cluster; unique.';
COMMENT ON COLUMN core.deployment_cluster.created_at IS
'When the cluster was registered.';
