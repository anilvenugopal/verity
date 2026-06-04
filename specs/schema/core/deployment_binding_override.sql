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
COMMENT ON TABLE core.deployment_binding_override IS
'Per-binding real-or-mock override for a deployment: lets a specific Source/Target binding be mocked (with a canned payload) without changing the version. Safety rail: run_mode=shadow forcibly suppresses or mocks ALL Target Bindings regardless of these rows — enforced by the harness — so a shadow run can never write to a business system (ADR-0006).

@tier 1
@lifecycle mutable
@subject deploy
@invariant shadow run-mode suppresses all target writes regardless of these rows
@decision D8
@adr 0006';
COMMENT ON COLUMN core.deployment_binding_override.deployment_binding_override_id IS
'Identity of the override.';
COMMENT ON COLUMN core.deployment_binding_override.deployment_id IS
'The deployment this override applies to. @ref core.deployment hard';
COMMENT ON COLUMN core.deployment_binding_override.binding_kind IS
'Whether it overrides a source or a target binding. @values source|target';
COMMENT ON COLUMN core.deployment_binding_override.binding_name IS
'Which binding on the version, by name.';
COMMENT ON COLUMN core.deployment_binding_override.is_mocked IS
'Whether this binding is mocked rather than hitting the real backend.';
COMMENT ON COLUMN core.deployment_binding_override.mock_payload IS
'The canned payload returned when the binding is mocked.';
