-- core.canonical_requirement  ·  subject: compliance  ·  (table)

CREATE TABLE core.canonical_requirement (
    requirement_id        uuid       NOT NULL DEFAULT uuidv7(),  -- a VERSION
    requirement_code      text       NOT NULL,                   -- stable logical key
    governance_domain_code text      NOT NULL,
    title                 text       NOT NULL,
    text                  text       NOT NULL,
    embedding             vector(384),                            -- similarity / semantic mapping (ADR-0009)
    valid_from            timestamptz NOT NULL DEFAULT now(),
    valid_to              timestamptz,
    created_at            timestamptz NOT NULL DEFAULT now(),
    CONSTRAINT pk_canonical_requirement PRIMARY KEY (requirement_id),
    CONSTRAINT fk_canonical_requirement_domain FOREIGN KEY (governance_domain_code)
        REFERENCES reference.governance_domain (code) ON DELETE RESTRICT);
COMMENT ON TABLE core.canonical_requirement IS 'tier:1 SCD-2. Center axis: the stable, technology-agnostic requirement vocabulary, grouped by governance_domain. Versions for as-of reproducibility. ADR-0008/D7.';
CREATE UNIQUE INDEX uq_canonical_requirement_current ON core.canonical_requirement (requirement_code) WHERE valid_to IS NULL;
CREATE INDEX ix_canonical_requirement_domain ON core.canonical_requirement (governance_domain_code);
