-- core.deployment_environment  ·  subject: deploy  ·  (table)

CREATE TABLE core.deployment_environment (
    deployment_environment_id uuid  NOT NULL DEFAULT uuidv7(),
    name                  text       NOT NULL,
    environment_kind_code text       NOT NULL,                  -- non_prod | prod | ephemeral
    created_at            timestamptz NOT NULL DEFAULT now(),
    CONSTRAINT pk_deployment_environment PRIMARY KEY (deployment_environment_id),
    CONSTRAINT fk_deployment_environment_kind FOREIGN KEY (environment_kind_code) REFERENCES reference.environment_kind (code),
    CONSTRAINT uq_deployment_environment_name UNIQUE (name));
COMMENT ON TABLE core.deployment_environment IS
'A named environment that groups clusters and sets the deployment gate: prod, non_prod, or ephemeral (temporary/replay). The environment_kind feeds the lifecycle->environment matrix that decides which run-modes a version may use here (ADR-0006).

@tier 1
@lifecycle mutable
@subject deploy
@status reference.environment_kind
@decision D8
@adr 0006';
COMMENT ON COLUMN core.deployment_environment.deployment_environment_id IS
'Identity of the environment.';
COMMENT ON COLUMN core.deployment_environment.name IS
'Human name of the environment; unique.';
COMMENT ON COLUMN core.deployment_environment.environment_kind_code IS
'prod/non_prod/ephemeral — the class that drives lifecycle gating and reproducible replay. @status reference.environment_kind';
COMMENT ON COLUMN core.deployment_environment.created_at IS
'When the environment was created.';
