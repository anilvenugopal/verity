-- core.domain_maturity  ·  subject: compliance  ·  (table)

CREATE TABLE core.domain_maturity (
    domain_maturity_id    uuid       NOT NULL DEFAULT uuidv7(),
    governance_domain_code text      NOT NULL,
    application_id        uuid,                                    -- scope (NULL = platform-wide)
    score                 numeric(5,2) NOT NULL,                  -- normalized 0..100 (algorithm in component spec)
    max_tier_achieved     integer,
    coverage_level_code   text,
    computed_at           timestamptz  NOT NULL DEFAULT now(),
    CONSTRAINT pk_domain_maturity PRIMARY KEY (domain_maturity_id),
    CONSTRAINT fk_domain_maturity_domain FOREIGN KEY (governance_domain_code) REFERENCES reference.governance_domain (code),
    CONSTRAINT fk_domain_maturity_application FOREIGN KEY (application_id) REFERENCES core.application (application_id) ON DELETE RESTRICT,
    CONSTRAINT fk_domain_maturity_coverage FOREIGN KEY (coverage_level_code) REFERENCES reference.coverage_level (code));
COMMENT ON TABLE core.domain_maturity IS 'tier:1 append-only. Per-domain normalized maturity score snapshots (trend history). Latest via domain_maturity_current. D7.';
CREATE INDEX ix_domain_maturity_domain_time ON core.domain_maturity (governance_domain_code, application_id, computed_at DESC);
