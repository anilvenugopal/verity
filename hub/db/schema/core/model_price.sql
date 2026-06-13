-- core.model_price  ·  subject: decisions  ·  (table)

CREATE TABLE core.model_price (
    model_price_id      uuid        NOT NULL DEFAULT uuidv7(),
    model_id            uuid        NOT NULL,
    input_price_per_1k  numeric(12,6) NOT NULL,
    output_price_per_1k numeric(12,6) NOT NULL,
    currency_code       text        NOT NULL DEFAULT 'usd',
    valid_from          timestamptz  NOT NULL DEFAULT now(),
    valid_to            timestamptz NOT NULL DEFAULT '2099-12-31 00:00:00+00',
    created_at          timestamptz  NOT NULL DEFAULT now(),
    CONSTRAINT pk_model_price PRIMARY KEY (model_price_id),
    CONSTRAINT fk_model_price_model FOREIGN KEY (model_id) REFERENCES core.model (model_id) ON DELETE RESTRICT,
    CONSTRAINT fk_model_price_currency FOREIGN KEY (currency_code) REFERENCES reference.currency (code));
COMMENT ON TABLE core.model_price IS
'Per-model price windows (input/output per 1,000 tokens). Cost is NEVER stored on an invocation — it is computed point-in-time via v_model_invocation_cost by joining the price in effect at the invocation timestamp, so historic costs stay stable across later price edits.

@tier 1
@lifecycle scd2
@subject decisions
@status reference.currency';
CREATE UNIQUE INDEX uq_model_price_open ON core.model_price (model_id) WHERE valid_to = '2099-12-31 00:00:00+00';
COMMENT ON COLUMN core.model_price.model_price_id IS
'Identity of this price window.';
COMMENT ON COLUMN core.model_price.model_id IS
'The priced model. @ref core.model hard';
COMMENT ON COLUMN core.model_price.input_price_per_1k IS
'Input token price per 1,000 tokens, in currency_code.';
COMMENT ON COLUMN core.model_price.output_price_per_1k IS
'Output token price per 1,000 tokens.';
COMMENT ON COLUMN core.model_price.currency_code IS
'Currency of the prices. @status reference.currency';
COMMENT ON COLUMN core.model_price.valid_from IS
'Start of the SCD-2 validity window.';
COMMENT ON COLUMN core.model_price.valid_to IS
'End of the window; the open row (2099-12-31) is current.';
COMMENT ON COLUMN core.model_price.created_at IS
'When this window was recorded.';
