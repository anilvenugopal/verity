-- core.canonical_requirement  ·  subject: compliance  ·  (table)

CREATE TABLE core.canonical_requirement (
    requirement_id        uuid       NOT NULL DEFAULT uuidv7(),  -- a VERSION
    requirement_code      text       NOT NULL,                   -- stable logical key
    governance_domain_code text      NOT NULL,
    title                 text       NOT NULL,
    text                  text       NOT NULL,
    embedding             vector(384),                            -- similarity / semantic mapping (ADR-0009)
    valid_from            timestamptz NOT NULL DEFAULT now(),
    valid_to              timestamptz NOT NULL DEFAULT '2099-12-31 00:00:00+00',
    created_at            timestamptz NOT NULL DEFAULT now(),
    CONSTRAINT pk_canonical_requirement PRIMARY KEY (requirement_id),
    CONSTRAINT fk_canonical_requirement_domain FOREIGN KEY (governance_domain_code)
        REFERENCES reference.governance_domain (code) ON DELETE RESTRICT);
COMMENT ON TABLE core.canonical_requirement IS
'Center axis: the stable, technology-agnostic requirement vocabulary that regulations map INTO and controls map OUT OF, grouped by governance domain. Versioned for as-of reproducibility; carries a pgvector embedding for semantic mapping (ADR-0008, ADR-0009, D7).

@tier 1
@lifecycle scd2
@subject compliance
@status reference.governance_domain
@adr 0008';
CREATE UNIQUE INDEX uq_canonical_requirement_current ON core.canonical_requirement (requirement_code) WHERE valid_to = '2099-12-31 00:00:00+00';
CREATE INDEX ix_canonical_requirement_domain ON core.canonical_requirement (governance_domain_code);
COMMENT ON COLUMN core.canonical_requirement.requirement_id IS
'Identity of this VERSION; the surrogate provisions, controls and obligations pin to.';
COMMENT ON COLUMN core.canonical_requirement.requirement_code IS
'Stable logical key shared across versions.';
COMMENT ON COLUMN core.canonical_requirement.governance_domain_code IS
'The governance domain this requirement sits in. @status reference.governance_domain';
COMMENT ON COLUMN core.canonical_requirement.title IS
'Short title of the requirement.';
COMMENT ON COLUMN core.canonical_requirement.text IS
'Full requirement statement.';
COMMENT ON COLUMN core.canonical_requirement.embedding IS
'pgvector embedding for semantic mapping and similarity (ADR-0009).';
COMMENT ON COLUMN core.canonical_requirement.valid_from IS
'Start of the SCD-2 validity window.';
COMMENT ON COLUMN core.canonical_requirement.valid_to IS
'End of the window; the open row (2099-12-31) is the current version.';
COMMENT ON COLUMN core.canonical_requirement.created_at IS
'When this version was recorded.';
