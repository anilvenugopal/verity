-- core.model_price  ·  subject: decisions  ·  (table)

CREATE TABLE core.model_price (
    model_price_id      uuid        NOT NULL DEFAULT uuidv7(),
    model_id            uuid        NOT NULL,
    input_price_per_1k  numeric(12,6) NOT NULL,
    output_price_per_1k numeric(12,6) NOT NULL,
    currency_code       text        NOT NULL DEFAULT 'usd',
    valid_from          timestamptz  NOT NULL DEFAULT now(),
    valid_to            timestamptz,
    created_at          timestamptz  NOT NULL DEFAULT now(),
    CONSTRAINT pk_model_price PRIMARY KEY (model_price_id),
    CONSTRAINT fk_model_price_model FOREIGN KEY (model_id) REFERENCES core.model (model_id) ON DELETE RESTRICT,
    CONSTRAINT fk_model_price_currency FOREIGN KEY (currency_code) REFERENCES reference.currency (code));
COMMENT ON TABLE core.model_price IS 'tier:1 SCD-2. Per-model price windows (valid_from/valid_to). Cost is computed point-in-time, never stored.';
CREATE UNIQUE INDEX uq_model_price_open ON core.model_price (model_id) WHERE valid_to IS NULL;
