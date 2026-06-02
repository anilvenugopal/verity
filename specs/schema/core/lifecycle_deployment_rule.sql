-- core.lifecycle_deployment_rule  ·  subject: deploy  ·  (table)

CREATE TABLE core.lifecycle_deployment_rule (
    lifecycle_state_code  text       NOT NULL,
    environment_kind_code text       NOT NULL,
    allowed_run_modes     text[]     NOT NULL,                  -- subset of {live,shadow,ab,locked}
    output_suppressed     boolean     NOT NULL DEFAULT false,
    CONSTRAINT pk_lifecycle_deployment_rule PRIMARY KEY (lifecycle_state_code, environment_kind_code),
    CONSTRAINT fk_ldr_state FOREIGN KEY (lifecycle_state_code) REFERENCES reference.lifecycle_state (code),
    CONSTRAINT fk_ldr_env FOREIGN KEY (environment_kind_code) REFERENCES reference.environment_kind (code));
COMMENT ON TABLE core.lifecycle_deployment_rule IS 'tier:1. The ADR-0006 lifecycle->environment matrix as auditable DATA: which run-modes a state may use per environment, and whether outputs suppress. The deploy gate reads this. D8.';
INSERT INTO core.lifecycle_deployment_rule (lifecycle_state_code, environment_kind_code, allowed_run_modes, output_suppressed) VALUES
    ('staging',   'non_prod',  ARRAY['live'],            false),
    ('challenger','prod',      ARRAY['shadow','ab'],     false),
    ('challenger','ephemeral', ARRAY['shadow','ab'],     false),
    ('champion',  'prod',      ARRAY['live'],            false),
    ('champion',  'non_prod',  ARRAY['live'],            false),
    ('champion',  'ephemeral', ARRAY['live','shadow'],   false),
    ('deprecated','prod',      ARRAY['locked'],          true),
    ('deprecated','ephemeral', ARRAY['locked','shadow'], true);
