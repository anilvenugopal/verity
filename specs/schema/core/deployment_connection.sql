-- core.deployment_connection  ·  subject: deploy  ·  (table)

CREATE TABLE core.deployment_connection (
    deployment_connection_id uuid    NOT NULL DEFAULT uuidv7(),
    deployment_id         uuid       NOT NULL,
    data_connector_version_id uuid   NOT NULL,                  -- the env-specific backend
    purpose               text,
    config                jsonb      NOT NULL DEFAULT '{}'::jsonb,
    CONSTRAINT pk_deployment_connection PRIMARY KEY (deployment_connection_id),
    CONSTRAINT fk_deployment_connection_deployment FOREIGN KEY (deployment_id) REFERENCES core.deployment (deployment_id) ON DELETE CASCADE,
    CONSTRAINT fk_deployment_connection_connector FOREIGN KEY (data_connector_version_id) REFERENCES core.data_connector_version (data_connector_version_id) ON DELETE RESTRICT);
COMMENT ON TABLE core.deployment_connection IS
'Binds a deployment to the environment-specific data-connector versions it uses, so the same package runs against dev/staging/prod backends without rebuilding. These are also materialized into the package bundle, keeping the harness self-contained at runtime (D8).

@tier 1
@lifecycle mutable
@subject deploy
@decision D8';
COMMENT ON COLUMN core.deployment_connection.deployment_connection_id IS
'Identity of the wiring row.';
COMMENT ON COLUMN core.deployment_connection.deployment_id IS
'The deployment this connection belongs to. @ref core.deployment hard';
COMMENT ON COLUMN core.deployment_connection.data_connector_version_id IS
'The environment-specific backend the deployment talks to. @ref core.data_connector_version hard';
COMMENT ON COLUMN core.deployment_connection.purpose IS
'What the connection is for (e.g. source store, target store) when a deployment has several.';
COMMENT ON COLUMN core.deployment_connection.config IS
'Connection-specific configuration overlaid for this deployment.';
