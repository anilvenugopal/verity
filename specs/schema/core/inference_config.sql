-- core.inference_config  ·  subject: registry  ·  (table)

CREATE TABLE core.inference_config (
    inference_config_id uuid        NOT NULL DEFAULT uuidv7(),
    max_tokens          integer,
    temperature         numeric(4,3),
    params              jsonb        NOT NULL DEFAULT '{}'::jsonb,  -- additional model params (genuinely variable)
    created_at          timestamptz  NOT NULL DEFAULT now(),
    CONSTRAINT pk_inference_config PRIMARY KEY (inference_config_id),
    CONSTRAINT ck_inference_config_temp CHECK (temperature IS NULL OR (temperature >= 0 AND temperature <= 2))
);
COMMENT ON TABLE core.inference_config IS 'tier:1. Inference parameters for an executable_version. The MODEL is decoupled: resolved via an ORDERED list of model_references (inference_config_model, in 06-decisions) — primary + fallbacks. Lets the underlying model be swapped centrally (rebind the reference) with NO package re-promotion, and gives per-executable fallback. NO hard model_id here.';
