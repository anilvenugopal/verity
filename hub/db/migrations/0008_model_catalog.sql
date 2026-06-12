-- 0008_model_catalog: seed the Anthropic Claude 4 model catalog for existing databases.
-- Idempotent via ON CONFLICT DO NOTHING. New installs get this from core_seed.sql (0001_baseline);
-- existing DBs that pre-date the model catalog additions need this forward migration.

-- Bootstrap automation actor (may already exist from core_seed.sql on new installs)
INSERT INTO core.actor (actor_id, actor_type_code, display_name, primary_role_code, created_by_actor_id)
VALUES ('00000000-0000-0000-0000-000000000001'::uuid, 'automation', 'Verity Seed', 'ai_governance', NULL)
ON CONFLICT (actor_id) DO NOTHING;

-- Provider models (current Anthropic Claude 4 family)
INSERT INTO core.model (model_code, provider, modality, model_status_code) VALUES
    ('claude-opus-4-8',   'anthropic', 'chat', 'active'),
    ('claude-sonnet-4-6', 'anthropic', 'chat', 'active'),
    ('claude-haiku-4-5',  'anthropic', 'chat', 'active')
ON CONFLICT (model_code) DO NOTHING;

-- Standard logical model references
INSERT INTO core.model_reference (reference_code, name, description) VALUES
    ('reasoning-primary',     'Reasoning Primary',      'Default for agentic / assessment tasks'),
    ('reasoning-fallback',    'Reasoning Fallback',     'Fallback for reasoning tasks'),
    ('extraction-primary',    'Extraction Primary',     'Lighter tasks, higher throughput'),
    ('extraction-fallback',   'Extraction Fallback',    'Fallback for extraction tasks'),
    ('classification-primary','Classification Primary', 'Classification, low-latency')
ON CONFLICT (reference_code) DO NOTHING;

-- Initial model_reference_binding rows
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

-- June 2025 list prices (USD, per 1k tokens)
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

