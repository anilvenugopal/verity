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

-- -------------------------------------------------------------------------
-- Model catalog seed (ADR-0019 / design decision D10)
-- Standard Anthropic models, stable logical references, and initial bindings.
-- Apply AFTER reference_seed.sql (reference.model_status, reference.role,
-- reference.actor_type must exist).
-- -------------------------------------------------------------------------

-- Bootstrap automation actor for seed-time operations (NULL created_by_actor_id
-- is the only valid nil; see core.actor schema comment).
INSERT INTO core.actor (actor_id, actor_type_code, display_name, primary_role_code, created_by_actor_id) VALUES
    ('00000000-0000-0000-0000-000000000001'::uuid, 'automation', 'Verity Seed', 'ai_governance', NULL)
    ON CONFLICT (actor_id) DO NOTHING;

-- Provider models (current Anthropic Claude 4 family)
INSERT INTO core.model (model_code, provider, modality, model_status_code) VALUES
    ('claude-opus-4-8',   'anthropic', 'chat', 'active'),
    ('claude-sonnet-4-6', 'anthropic', 'chat', 'active'),
    ('claude-haiku-4-5',  'anthropic', 'chat', 'active')
    ON CONFLICT (model_code) DO NOTHING;

-- Standard logical model references (stable aliases; executables point at these,
-- not at concrete model strings — see ADR-0019 and design decision D10).
INSERT INTO core.model_reference (reference_code, name, description) VALUES
    ('reasoning-primary',     'Reasoning Primary',      'Default for agentic / assessment tasks'),
    ('reasoning-fallback',    'Reasoning Fallback',     'Fallback for reasoning tasks'),
    ('extraction-primary',    'Extraction Primary',     'Lighter tasks, higher throughput'),
    ('extraction-fallback',   'Extraction Fallback',    'Fallback for extraction tasks'),
    ('classification-primary','Classification Primary', 'Classification, low-latency')
    ON CONFLICT (reference_code) DO NOTHING;

-- Initial model_reference_binding rows — one open SCD-2 window per reference.
-- Operators close and re-open these via POST /api/registry/model-references/:id/bind
-- without requiring re-promotion of any executable.
INSERT INTO core.model_reference_binding
    (model_reference_id, model_id, valid_from, valid_to, reason, bound_by_actor_id, bound_role_code)
SELECT
    mr.model_reference_id,
    m.model_id,
    now(),
    '2099-12-31 00:00:00+00'::timestamptz,
    'initial seed',
    '00000000-0000-0000-0000-000000000001'::uuid,
    'ai_governance'
FROM (VALUES
    ('reasoning-primary',     'claude-opus-4-8'),
    ('reasoning-fallback',    'claude-sonnet-4-6'),
    ('extraction-primary',    'claude-sonnet-4-6'),
    ('extraction-fallback',   'claude-haiku-4-5'),
    ('classification-primary','claude-haiku-4-5')
) AS seed(ref_code, model_code)
JOIN core.model_reference mr ON mr.reference_code = seed.ref_code
JOIN core.model            m  ON m.model_code      = seed.model_code
ON CONFLICT DO NOTHING;

-- Initial model prices (open SCD-2 window). Input/output per 1k tokens, USD.
-- These are June 2025 list prices; operators update via POST /api/registry/models/:id/prices.
INSERT INTO core.model_price (model_id, input_price_per_1k, output_price_per_1k, currency_code)
SELECT m.model_id, seed.input_p, seed.output_p, 'usd'
FROM (VALUES
    ('claude-opus-4-8',   15.00,  75.00),
    ('claude-sonnet-4-6',  3.00,  15.00),
    ('claude-haiku-4-5',   0.80,   4.00)
) AS seed(model_code, input_p, output_p)
JOIN core.model m ON m.model_code = seed.model_code
WHERE NOT EXISTS (
    SELECT 1 FROM core.model_price p
    WHERE p.model_id = m.model_id AND p.valid_to = '2099-12-31 00:00:00+00'
);
