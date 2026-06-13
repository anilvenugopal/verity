-- registry_model_catalog.sql — feature 005 (US6).
-- Provider models, SCD-2 price windows, stable model references, and
-- SCD-2 reference-to-model bindings.

-- ── Models ────────────────────────────────────────────────────────────────────

-- name: create_model^
INSERT INTO core.model (model_code, provider, modality)
VALUES (%(model_code)s, %(provider)s, %(modality)s)
RETURNING model_id, model_code, provider, modality, model_status_code;

-- name: get_model_by_code^
SELECT model_id, model_code, provider, modality, model_status_code
FROM core.model WHERE model_code = %(model_code)s;

-- name: list_models
SELECT m.model_id, m.model_code, m.provider, m.modality, m.model_status_code, m.context_window,
       p.model_price_id, p.input_price_per_1k, p.output_price_per_1k,
       p.currency_code, p.valid_from AS price_valid_from
FROM core.model m
LEFT JOIN core.model_price p ON p.model_id = m.model_id
    AND p.valid_to = '2099-12-31 00:00:00+00'
ORDER BY m.model_code;

-- ── Model Prices ──────────────────────────────────────────────────────────────

-- name: add_model_price^
INSERT INTO core.model_price (model_id, input_price_per_1k, output_price_per_1k, currency_code)
VALUES (%(model_id)s, %(input_price_per_1k)s, %(output_price_per_1k)s, %(currency_code)s)
RETURNING model_price_id, model_id, input_price_per_1k, output_price_per_1k,
          currency_code, valid_from, valid_to;

-- name: close_current_model_price!
UPDATE core.model_price
SET valid_to = now()
WHERE model_id = %(model_id)s
  AND valid_to = '2099-12-31 00:00:00+00';

-- name: list_model_prices
SELECT model_price_id, model_id, input_price_per_1k, output_price_per_1k,
       currency_code, valid_from, valid_to
FROM core.model_price WHERE model_id = %(model_id)s ORDER BY valid_from DESC;

-- ── Model References ──────────────────────────────────────────────────────────

-- name: create_model_reference^
INSERT INTO core.model_reference (reference_code, name, description)
VALUES (%(reference_code)s, %(name)s, %(description)s)
RETURNING model_reference_id, reference_code, name;

-- name: list_model_references
SELECT r.model_reference_id, r.reference_code, r.name,
       m.model_code AS current_model_code
FROM core.model_reference r
LEFT JOIN core.model_reference_binding b ON b.model_reference_id = r.model_reference_id
    AND b.valid_to = '2099-12-31 00:00:00+00'
LEFT JOIN core.model m ON m.model_id = b.model_id
ORDER BY r.reference_code;

-- ── Model Reference Bindings ──────────────────────────────────────────────────

-- name: bind_model_reference^
INSERT INTO core.model_reference_binding
    (model_reference_id, model_id, reason, bound_by_actor_id, bound_role_code)
VALUES (%(model_reference_id)s, %(model_id)s, %(reason)s, %(bound_by_actor_id)s, %(bound_role_code)s)
RETURNING model_reference_binding_id, model_reference_id, model_id,
          valid_from, valid_to, reason;

-- name: close_current_reference_binding!
UPDATE core.model_reference_binding
SET valid_to = now()
WHERE model_reference_id = %(model_reference_id)s
  AND valid_to = '2099-12-31 00:00:00+00';

-- name: list_model_reference_bindings
SELECT mrb.model_reference_binding_id, mrb.model_reference_id, mrb.model_id,
       m.model_code, mrb.valid_from, mrb.valid_to, mrb.reason
FROM core.model_reference_binding mrb
JOIN core.model m ON m.model_id = mrb.model_id
WHERE mrb.model_reference_id = %(model_reference_id)s
ORDER BY mrb.valid_from DESC;

-- ── Inference Config Chain ────────────────────────────────────────────────────
-- Returns ordered (priority, model_reference_id, reference_code, resolved model_code)
-- joined via the current open model_reference_binding. This is the cross-feature contract
-- that Feature 008's gateway_llm_call depends on (ADR-0019 §4).

-- name: get_inference_config_chain
SELECT icm.priority, icm.model_reference_id, mr.reference_code,
       m.model_code AS resolved_model_code
FROM core.inference_config_model icm
JOIN core.model_reference mr ON mr.model_reference_id = icm.model_reference_id
LEFT JOIN core.model_reference_binding mrb ON mrb.model_reference_id = icm.model_reference_id
    AND mrb.valid_to = '2099-12-31 00:00:00+00'
LEFT JOIN core.model m ON m.model_id = mrb.model_id
WHERE icm.inference_config_id = %(inference_config_id)s
ORDER BY icm.priority;
