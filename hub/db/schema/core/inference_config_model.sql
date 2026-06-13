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
COMMENT ON TABLE core.inference_config_model IS
'The ordered model_references an executable_version uses: priority 1 is the primary, 2+ are fallbacks tried in order when a provider is unavailable or errors. This is the per-executable fallback chain (D10); each reference resolves to an actual model via its current binding.

@tier 1
@lifecycle mutable
@subject decisions
@decision D10';
COMMENT ON COLUMN core.inference_config_model.inference_config_id IS
'The inference config this chain belongs to. @ref core.inference_config hard';
COMMENT ON COLUMN core.inference_config_model.model_reference_id IS
'A model reference in the chain. @ref core.model_reference hard';
COMMENT ON COLUMN core.inference_config_model.priority IS
'1 = primary; 2,3… = fallbacks tried in order. At least 1.';
