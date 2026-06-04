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
COMMENT ON TABLE core.domain_maturity IS
'Append-only snapshots of a governance domain''s normalized maturity score (0–100), optionally scoped to an application, for trend history. The scoring algorithm lives in the component spec; the latest snapshot per (domain, scope) is domain_maturity_current (D7).

@tier 1
@lifecycle append-only
@subject compliance
@status reference.coverage_level
@decision D7';
CREATE INDEX ix_domain_maturity_domain_time ON core.domain_maturity (governance_domain_code, application_id, computed_at DESC);
COMMENT ON COLUMN core.domain_maturity.domain_maturity_id IS
'Identity of the snapshot.';
COMMENT ON COLUMN core.domain_maturity.governance_domain_code IS
'The governance domain scored. @status reference.governance_domain';
COMMENT ON COLUMN core.domain_maturity.application_id IS
'The application scope; null = platform-wide. @ref core.application hard';
COMMENT ON COLUMN core.domain_maturity.score IS
'Normalized maturity score, 0–100.';
COMMENT ON COLUMN core.domain_maturity.max_tier_achieved IS
'Highest requirement tier achieved in the domain.';
COMMENT ON COLUMN core.domain_maturity.coverage_level_code IS
'Coverage classification for the score. @status reference.coverage_level';
COMMENT ON COLUMN core.domain_maturity.computed_at IS
'When the snapshot was computed; latest is current.';
