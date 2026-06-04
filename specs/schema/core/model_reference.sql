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
COMMENT ON TABLE core.model_reference IS
'A stable logical model alias (e.g. ''reasoning-primary'') that inference configs point at instead of a concrete model. It resolves to an actual model through an effective-dated binding, so the underlying model can be swapped centrally — close the binding, open a new one — and every package using the reference follows with no re-promotion (D10).

@tier 1
@lifecycle mutable
@subject decisions
@decision D10';
COMMENT ON COLUMN core.model_reference.model_reference_id IS
'Identity of the alias.';
COMMENT ON COLUMN core.model_reference.reference_code IS
'Stable alias, e.g. reasoning-primary; unique. Inference configs point at this, not at a model.';
COMMENT ON COLUMN core.model_reference.name IS
'Human name of the reference.';
COMMENT ON COLUMN core.model_reference.description IS
'What the reference is for.';
COMMENT ON COLUMN core.model_reference.created_at IS
'When created.';
COMMENT ON COLUMN core.model_reference.updated_at IS
'When last updated.';
