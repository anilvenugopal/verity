-- core.deployment_environment  ·  subject: deploy  ·  (table)

CREATE TABLE core.deployment_environment (
    deployment_environment_id uuid  NOT NULL DEFAULT uuidv7(),
    name                  text       NOT NULL,
    environment_kind_code text       NOT NULL,                  -- non_prod | prod | ephemeral
    created_at            timestamptz NOT NULL DEFAULT now(),
    CONSTRAINT pk_deployment_environment PRIMARY KEY (deployment_environment_id),
    CONSTRAINT fk_deployment_environment_kind FOREIGN KEY (environment_kind_code) REFERENCES reference.environment_kind (code),
    CONSTRAINT uq_deployment_environment_name UNIQUE (name));
