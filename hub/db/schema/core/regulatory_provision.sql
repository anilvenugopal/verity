-- core.regulatory_provision  ·  subject: compliance  ·  (table)

CREATE TABLE core.regulatory_provision (
    provision_id         uuid        NOT NULL DEFAULT uuidv7(),  -- a VERSION of the provision
    provision_code       text        NOT NULL,                   -- stable logical key
    framework_code       text        NOT NULL,
    citation             text        NOT NULL,                   -- e.g. "SR 11-7 §III.A"
    jurisdiction         text,
    text                 text,
    valid_from           timestamptz  NOT NULL DEFAULT now(),
    valid_to             timestamptz NOT NULL DEFAULT '2099-12-31 00:00:00+00',
    created_at           timestamptz  NOT NULL DEFAULT now(),
    CONSTRAINT pk_regulatory_provision PRIMARY KEY (provision_id),
    CONSTRAINT fk_regulatory_provision_framework FOREIGN KEY (framework_code)
        REFERENCES core.regulatory_framework (framework_code) ON DELETE RESTRICT);
COMMENT ON TABLE core.regulatory_provision IS
'Left axis: a citable provision within a framework (e.g. "SR 11-7 §III.A"), versioned over time as it is amended (SCD-2, D7). Bridges and obligations pin the version surrogate, so a mapping always resolves the exact as-of text (ADR-0008, ADR-0009).

@tier 1
@lifecycle scd2
@subject compliance
@adr 0008';
CREATE UNIQUE INDEX uq_regulatory_provision_current ON core.regulatory_provision (provision_code) WHERE valid_to = '2099-12-31 00:00:00+00';
CREATE INDEX ix_regulatory_provision_framework ON core.regulatory_provision (framework_code);
COMMENT ON COLUMN core.regulatory_provision.provision_id IS
'Identity of this VERSION of the provision; the surrogate other rows pin to.';
COMMENT ON COLUMN core.regulatory_provision.provision_code IS
'Stable logical key shared across versions.';
COMMENT ON COLUMN core.regulatory_provision.framework_code IS
'The framework this provision belongs to. @ref core.regulatory_framework hard';
COMMENT ON COLUMN core.regulatory_provision.citation IS
'The formal citation, e.g. "SR 11-7 §III.A".';
COMMENT ON COLUMN core.regulatory_provision.jurisdiction IS
'Jurisdiction the provision applies in.';
COMMENT ON COLUMN core.regulatory_provision.text IS
'The provision text for this version.';
COMMENT ON COLUMN core.regulatory_provision.valid_from IS
'Start of the SCD-2 validity window.';
COMMENT ON COLUMN core.regulatory_provision.valid_to IS
'End of the window; the open row (2099-12-31) is the current version.';
COMMENT ON COLUMN core.regulatory_provision.created_at IS
'When this version was recorded.';
