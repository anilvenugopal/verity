-- core.provision_requirement  ·  subject: compliance  ·  (table)

CREATE TABLE core.provision_requirement (
    provision_requirement_id uuid    NOT NULL DEFAULT uuidv7(),
    provision_id          uuid       NOT NULL,                    -- pinned provision version
    requirement_id        uuid       NOT NULL,                    -- pinned requirement version
    min_tier_level        integer     NOT NULL DEFAULT 1,         -- minimum cumulative tier this provision demands
    derivation_method_code text      NOT NULL DEFAULT 'manual',   -- how the mapping was established (D9)
    valid_from            timestamptz NOT NULL DEFAULT now(),
    valid_to              timestamptz,
    created_at            timestamptz NOT NULL DEFAULT now(),
    CONSTRAINT pk_provision_requirement PRIMARY KEY (provision_requirement_id),
    CONSTRAINT fk_provreq_provision FOREIGN KEY (provision_id) REFERENCES core.regulatory_provision (provision_id) ON DELETE RESTRICT,
    CONSTRAINT fk_provreq_requirement FOREIGN KEY (requirement_id) REFERENCES core.canonical_requirement (requirement_id) ON DELETE RESTRICT,
    CONSTRAINT fk_provreq_method FOREIGN KEY (derivation_method_code) REFERENCES reference.derivation_method (code),
    CONSTRAINT ck_provreq_min_tier CHECK (min_tier_level >= 1));
COMMENT ON TABLE core.provision_requirement IS 'tier:1 SCD-2. Bridge 1: many-to-many provision->requirement with min-tier. Effective-dated (mappings change as regs are mapped). derivation_method = manual/reasoner/human-validated (ADR-0009).';
