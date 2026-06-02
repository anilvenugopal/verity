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
COMMENT ON TABLE core.deployment_connection IS 'tier:1. Env-specific connections for a deployment; also materialized into the package bundle so the harness is self-contained at core. D8.';
