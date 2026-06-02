-- core.inference_config_model  ·  subject: decisions  ·  (table)

-- executable-level FALLBACK chain: an inference_config uses an ORDERED list of references.
CREATE TABLE core.inference_config_model (
    inference_config_id uuid        NOT NULL,
    model_reference_id  uuid        NOT NULL,
    priority            integer      NOT NULL,                  -- 1 = primary; 2,3… = fallbacks (tried in order)
    CONSTRAINT pk_inference_config_model PRIMARY KEY (inference_config_id, priority),
    CONSTRAINT fk_icm_config FOREIGN KEY (inference_config_id) REFERENCES core.inference_config (inference_config_id) ON DELETE CASCADE,
    CONSTRAINT fk_icm_reference FOREIGN KEY (model_reference_id) REFERENCES core.model_reference (model_reference_id) ON DELETE RESTRICT,
    CONSTRAINT uq_inference_config_model_ref UNIQUE (inference_config_id, model_reference_id),
    CONSTRAINT ck_inference_config_model_priority CHECK (priority >= 1));
COMMENT ON TABLE core.inference_config_model IS 'tier:1. The ordered model_references an executable_version uses: priority 1 = primary, 2+ = fallbacks. Per-executable fallback (D): the harness tries the next reference when a provider is unavailable/errors. Each reference resolves to an actual model via its current binding.';
