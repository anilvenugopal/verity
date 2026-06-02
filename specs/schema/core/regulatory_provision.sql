-- core.regulatory_provision  ·  subject: compliance  ·  (table)

CREATE TABLE core.regulatory_provision (
    provision_id         uuid        NOT NULL DEFAULT uuidv7(),  -- a VERSION of the provision
    provision_code       text        NOT NULL,                   -- stable logical key
    framework_code       text        NOT NULL,
    citation             text        NOT NULL,                   -- e.g. "SR 11-7 §III.A"
    jurisdiction         text,
    text                 text,
    valid_from           timestamptz  NOT NULL DEFAULT now(),
    valid_to             timestamptz,
    created_at           timestamptz  NOT NULL DEFAULT now(),
    CONSTRAINT pk_regulatory_provision PRIMARY KEY (provision_id),
    CONSTRAINT fk_regulatory_provision_framework FOREIGN KEY (framework_code)
        REFERENCES core.regulatory_framework (framework_code) ON DELETE RESTRICT);
COMMENT ON TABLE core.regulatory_provision IS 'tier:1 SCD-2. Left axis: a citable provision within a framework; versions over time (amendments). ADR-0008/D7.';
CREATE UNIQUE INDEX uq_regulatory_provision_current ON core.regulatory_provision (provision_code) WHERE valid_to IS NULL;
CREATE INDEX ix_regulatory_provision_framework ON core.regulatory_provision (framework_code);
