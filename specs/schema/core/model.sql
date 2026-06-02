-- core.model  ·  subject: decisions  ·  (table)

CREATE TABLE core.model (
    model_id            uuid        NOT NULL DEFAULT uuidv7(),
    model_code          text        NOT NULL,                  -- e.g. 'claude-sonnet-4-6'
    provider            text        NOT NULL,
    modality            text        NOT NULL DEFAULT 'chat',
    model_status_code   text        NOT NULL DEFAULT 'active',
    created_at          timestamptz  NOT NULL DEFAULT now(),
    updated_at          timestamptz  NOT NULL DEFAULT now(),
    CONSTRAINT pk_model PRIMARY KEY (model_id),
    CONSTRAINT fk_model_status FOREIGN KEY (model_status_code) REFERENCES reference.model_status (code),
    CONSTRAINT uq_model_code UNIQUE (model_code));
COMMENT ON TABLE core.model IS 'tier:1. Model registry (identity stable; pricing is SCD-2 in model_price).';
