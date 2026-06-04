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
COMMENT ON TABLE core.inference_config IS
'The inference parameters (max_tokens, temperature, extra params) for an executable_version. Deliberately holds NO model id: the model is resolved through an ordered list of model_references (inference_config_model) — a primary plus fallbacks — so the underlying model can be swapped centrally by rebinding the reference, with no package re-promotion, and each executable gets its own fallback chain (D10).

@tier 1
@lifecycle mutable
@subject registry
@decision D10';
COMMENT ON COLUMN core.inference_config.inference_config_id IS
'Identity of the inference config.';
COMMENT ON COLUMN core.inference_config.max_tokens IS
'Cap on output tokens; null = model default.';
COMMENT ON COLUMN core.inference_config.temperature IS
'Sampling temperature (0–2); null = model default.';
COMMENT ON COLUMN core.inference_config.params IS
'Additional, genuinely variable model parameters.';
COMMENT ON COLUMN core.inference_config.created_at IS
'When the config was created.';
