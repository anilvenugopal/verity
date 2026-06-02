-- core.deployment_binding_override  ·  subject: deploy  ·  (table)

CREATE TABLE core.deployment_binding_override (
    deployment_binding_override_id uuid NOT NULL DEFAULT uuidv7(),
    deployment_id         uuid       NOT NULL,
    binding_kind          text       NOT NULL,                  -- 'source' | 'target'
    binding_name          text       NOT NULL,                  -- which binding (by name on the version)
    is_mocked             boolean     NOT NULL DEFAULT false,    -- real vs mocked
    mock_payload          jsonb,
    CONSTRAINT pk_deployment_binding_override PRIMARY KEY (deployment_binding_override_id),
    CONSTRAINT fk_dbo_deployment FOREIGN KEY (deployment_id) REFERENCES core.deployment (deployment_id) ON DELETE CASCADE,
    CONSTRAINT ck_dbo_binding_kind CHECK (binding_kind IN ('source','target')),
    CONSTRAINT uq_dbo_deployment_binding UNIQUE (deployment_id, binding_kind, binding_name));
COMMENT ON TABLE core.deployment_binding_override IS 'tier:1. Per-binding real|mock override for a deployment. NOTE: run_mode=shadow FORCIBLY suppresses/mocks ALL Target Bindings regardless of these rows (the shadow safety rail; enforced by the harness). D8.';
