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

-- Regulatory frameworks an application may declare in scope (FR-IN-017). Starter set; extensible.
-- 'internal_only' / 'nist_ai_rmf' serve as the explicit "no external regime" sentinels (D-ONB).
INSERT INTO core.regulatory_framework (framework_code, name, authority) VALUES
    ('nist_ai_rmf','NIST AI Risk Management Framework','NIST'),
    ('naic_model_bulletin_ai','NAIC Model Bulletin on the Use of AI Systems by Insurers','NAIC'),
    ('colorado_sb21_169','Colorado SB21-169 (Insurance Anti-Discrimination)','Colorado DOI'),
    ('eu_ai_act','EU AI Act','European Union'),
    ('nydfs','NYDFS guidance','NY Dept of Financial Services'),
    ('iso_42001','ISO/IEC 42001 (AI Management System)','ISO/IEC'),
    ('internal_only','Internal governance only (no external regime)','Internal')
    ON CONFLICT (framework_code) DO NOTHING;
