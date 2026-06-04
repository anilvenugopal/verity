-- core.provision_requirement  ·  subject: compliance  ·  (table)

CREATE TABLE core.provision_requirement (
    provision_requirement_id uuid    NOT NULL DEFAULT uuidv7(),
    provision_id          uuid       NOT NULL,                    -- pinned provision version
    requirement_id        uuid       NOT NULL,                    -- pinned requirement version
    min_tier_level        integer     NOT NULL DEFAULT 1,         -- minimum cumulative tier this provision demands
    derivation_method_code text      NOT NULL DEFAULT 'manual',   -- how the mapping was established (D9)
    valid_from            timestamptz NOT NULL DEFAULT now(),
    valid_to              timestamptz NOT NULL DEFAULT '2099-12-31 00:00:00+00',
    created_at            timestamptz NOT NULL DEFAULT now(),
    CONSTRAINT pk_provision_requirement PRIMARY KEY (provision_requirement_id),
    CONSTRAINT fk_provreq_provision FOREIGN KEY (provision_id) REFERENCES core.regulatory_provision (provision_id) ON DELETE RESTRICT,
    CONSTRAINT fk_provreq_requirement FOREIGN KEY (requirement_id) REFERENCES core.canonical_requirement (requirement_id) ON DELETE RESTRICT,
    CONSTRAINT fk_provreq_method FOREIGN KEY (derivation_method_code) REFERENCES reference.derivation_method (code),
    CONSTRAINT ck_provreq_min_tier CHECK (min_tier_level >= 1));
COMMENT ON TABLE core.provision_requirement IS
'Bridge 1: the many-to-many mapping from a regulatory provision to the canonical requirement(s) it demands, with the minimum cumulative tier required. Effective-dated because mappings change as regulations are mapped; derivation_method records whether the mapping was manual, reasoner-recommended, or human-validated (ADR-0009).

@tier 1
@lifecycle scd2
@subject compliance
@status reference.derivation_method
@adr 0008';
COMMENT ON COLUMN core.provision_requirement.provision_requirement_id IS
'Identity of this VERSION of the mapping.';
COMMENT ON COLUMN core.provision_requirement.provision_id IS
'The pinned provision version. @ref core.regulatory_provision hard';
COMMENT ON COLUMN core.provision_requirement.requirement_id IS
'The pinned requirement version. @ref core.canonical_requirement hard';
COMMENT ON COLUMN core.provision_requirement.min_tier_level IS
'Minimum cumulative tier this provision demands of the requirement. At least 1.';
COMMENT ON COLUMN core.provision_requirement.derivation_method_code IS
'How the mapping was established — manual/reasoner/human-validated (D9). @status reference.derivation_method';
COMMENT ON COLUMN core.provision_requirement.valid_from IS
'Start of the SCD-2 validity window.';
COMMENT ON COLUMN core.provision_requirement.valid_to IS
'End of the window; the open row (2099-12-31) is the current version.';
COMMENT ON COLUMN core.provision_requirement.created_at IS
'When this version was recorded.';
