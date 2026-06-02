-- core.model_reference  ·  subject: decisions  ·  (table)

-- A model_reference is the STABLE alias the registry/inference_config points at (e.g.
-- 'reasoning-primary'). It resolves to an ACTUAL model via an effective-dated binding.
-- Swapping the underlying model = close the binding + open a new one — every package
-- using the reference follows, with NO re-promotion. Past runs resolve as-of (windows).
CREATE TABLE core.model_reference (
    model_reference_id  uuid        NOT NULL DEFAULT uuidv7(),
    reference_code      text        NOT NULL,                  -- stable alias, e.g. 'reasoning-primary'
    name                text        NOT NULL,
    description         text,
    created_at          timestamptz  NOT NULL DEFAULT now(),
    updated_at          timestamptz  NOT NULL DEFAULT now(),
    CONSTRAINT pk_model_reference PRIMARY KEY (model_reference_id),
    CONSTRAINT uq_model_reference_code UNIQUE (reference_code));
COMMENT ON TABLE core.model_reference IS 'tier:1. Stable logical model alias the registry points at; decouples packages from the actual model so it can be swapped centrally without re-promotion (legacy decoupling). Resolves via model_reference_binding.';
