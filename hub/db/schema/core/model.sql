-- core.model  ·  subject: decisions  ·  (table)

CREATE TABLE core.model (
    model_id            uuid        NOT NULL DEFAULT uuidv7(),
    model_code          text        NOT NULL,                  -- e.g. 'claude-sonnet-4-6'
    provider            text        NOT NULL,
    modality            text        NOT NULL DEFAULT 'chat',
    model_status_code   text        NOT NULL DEFAULT 'active',
    context_window      integer,
    created_at          timestamptz  NOT NULL DEFAULT now(),
    updated_at          timestamptz  NOT NULL DEFAULT now(),
    CONSTRAINT pk_model PRIMARY KEY (model_id),
    CONSTRAINT fk_model_status FOREIGN KEY (model_status_code) REFERENCES reference.model_status (code),
    CONSTRAINT uq_model_code UNIQUE (model_code));
COMMENT ON TABLE core.model IS
'The model registry: a stable identity for a provider model (model_code like ''claude-sonnet-4-6''). Identity is stable here; PRICING is SCD-2 in model_price, and which model a reference resolves to is SCD-2 in model_reference_binding (D10).

@tier 1
@lifecycle mutable
@subject decisions
@status reference.model_status';
COMMENT ON COLUMN core.model.model_id IS
'Identity of the model.';
COMMENT ON COLUMN core.model.model_code IS
'Stable provider model code, e.g. claude-sonnet-4-6; unique.';
COMMENT ON COLUMN core.model.provider IS
'Model provider.';
COMMENT ON COLUMN core.model.modality IS
'Model modality, e.g. chat.';
COMMENT ON COLUMN core.model.model_status_code IS
'Lifecycle status of the model in the registry. @status reference.model_status';
COMMENT ON COLUMN core.model.context_window IS
'Maximum context window in tokens for this model. Nullable — unknown for legacy rows.';
COMMENT ON COLUMN core.model.created_at IS
'When registered.';
COMMENT ON COLUMN core.model.updated_at IS
'When last updated.';
