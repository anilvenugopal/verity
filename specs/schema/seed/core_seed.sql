-- =====================================================================
-- seed/core_seed.sql — Verity v2 core data-driven config (seed)
-- Apply AFTER verity_schema.sql + reference_seed.sql. Idempotent. ADR-0011/0006.
-- =====================================================================

INSERT INTO core.lifecycle_deployment_rule (lifecycle_state_code, environment_kind_code, allowed_run_modes, output_suppressed) VALUES
    ('staging',   'non_prod',  ARRAY['live'],            false),
    ('challenger','prod',      ARRAY['shadow','ab'],     false),
    ('challenger','ephemeral', ARRAY['shadow','ab'],     false),
    ('champion',  'prod',      ARRAY['live'],            false),
    ('champion',  'non_prod',  ARRAY['live'],            false),
    ('champion',  'ephemeral', ARRAY['live','shadow'],   false),
    ('deprecated','prod',      ARRAY['locked'],          true),
    ('deprecated','ephemeral', ARRAY['locked','shadow'], true)
    ON CONFLICT (lifecycle_state_code, environment_kind_code) DO NOTHING;
