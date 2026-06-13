-- core.executable_version  ·  subject: registry  ·  (table)

CREATE TABLE core.executable_version (
    executable_version_id uuid       NOT NULL DEFAULT uuidv7(),
    executable_id         uuid       NOT NULL,
    kind_code             text       NOT NULL,                 -- denormalized from executable (enables agent-only FKs)
    semver                text       NOT NULL,                 -- e.g. '1.2.0'
    version_change_type_code text,                              -- major|minor|patch -> reference
    change_summary        text,
    cloned_from_version_id uuid,                                -- lineage (nullable)
    capability_type_code  text,                                 -- classification|extraction|… (may change per version)
    trust_level_code      text,
    governance_tier_code  text,
    data_classification_code text,
    inference_config_id   uuid,
    input_schema          jsonb,                                -- structured input payload schema
    output_schema         jsonb,                                -- structured output payload schema
    valid_from            timestamptz NOT NULL DEFAULT now(),                          -- SCD-2 temporal window
    valid_to              timestamptz NOT NULL DEFAULT '2099-12-31 00:00:00+00',
    created_at            timestamptz NOT NULL DEFAULT now(),
    created_by_actor_id   uuid       NOT NULL,
    created_role_code     text       NOT NULL,
    CONSTRAINT pk_executable_version PRIMARY KEY (executable_version_id),
    CONSTRAINT fk_executable_version_executable
        FOREIGN KEY (executable_id, kind_code)
        REFERENCES core.executable (executable_id, kind_code) ON DELETE RESTRICT,
    CONSTRAINT fk_executable_version_change_type FOREIGN KEY (version_change_type_code)
        REFERENCES reference.version_change_type (code) ON DELETE RESTRICT,
    CONSTRAINT fk_executable_version_cloned_from FOREIGN KEY (cloned_from_version_id)
        REFERENCES core.executable_version (executable_version_id) ON DELETE SET NULL,
    CONSTRAINT fk_executable_version_capability FOREIGN KEY (capability_type_code)
        REFERENCES reference.capability_type (code) ON DELETE RESTRICT,
    CONSTRAINT fk_executable_version_trust FOREIGN KEY (trust_level_code)
        REFERENCES reference.trust_level (code) ON DELETE RESTRICT,
    CONSTRAINT fk_executable_version_gov_tier FOREIGN KEY (governance_tier_code)
        REFERENCES reference.governance_tier (code) ON DELETE RESTRICT,
    CONSTRAINT fk_executable_version_data_class FOREIGN KEY (data_classification_code)
        REFERENCES reference.data_classification (code) ON DELETE RESTRICT,
    CONSTRAINT fk_executable_version_inference FOREIGN KEY (inference_config_id)
        REFERENCES core.inference_config (inference_config_id) ON DELETE RESTRICT,
    CONSTRAINT fk_executable_version_created_by FOREIGN KEY (created_by_actor_id)
        REFERENCES core.actor (actor_id) ON DELETE RESTRICT,
    CONSTRAINT fk_executable_version_created_role FOREIGN KEY (created_role_code)
        REFERENCES reference.role (code) ON DELETE RESTRICT,
    CONSTRAINT uq_executable_version_semver UNIQUE (executable_id, semver),
    -- composite unique lets agent-only component assignments pin kind via FK
    CONSTRAINT uq_executable_version_id_kind UNIQUE (executable_version_id, kind_code)
);
COMMENT ON TABLE core.executable_version IS
'An immutable, SCD-2 version of an executable — the thing everything else points at. Lifecycle, champion, bindings, packaging, deployment and runs all reference a VERSION, never an "agent or task". It carries the version''s composition (inference config, input/output schemas) and its governance classification (capability, trust, tier, data class). kind_code is denormalized so component assignments can enforce agent-only rules by composite FK (D5).

@tier 1
@lifecycle scd2
@subject registry
@status reference.capability_type
@status reference.trust_level
@status reference.governance_tier
@status reference.data_classification
@decision D5';
CREATE INDEX ix_executable_version_executable ON core.executable_version (executable_id);
COMMENT ON COLUMN core.executable_version.executable_version_id IS
'Identity of the version; the universal anchor for lifecycle, champion, bindings, packaging, deployment and runs.';
COMMENT ON COLUMN core.executable_version.executable_id IS
'The executable this is a version of. @ref core.executable hard';
COMMENT ON COLUMN core.executable_version.kind_code IS
'Denormalized from the executable so agent-only component assignments can pin the kind via composite FK. @status reference.executable_kind';
COMMENT ON COLUMN core.executable_version.semver IS
'Semantic version within the executable; unique per executable.';
COMMENT ON COLUMN core.executable_version.version_change_type_code IS
'major/minor/patch of this version relative to its predecessor. @status reference.version_change_type';
COMMENT ON COLUMN core.executable_version.change_summary IS
'What changed in this version.';
COMMENT ON COLUMN core.executable_version.cloned_from_version_id IS
'Lineage: the version this was cloned from, if any; set null if that ancestor is purged. @ref core.executable_version hard';
COMMENT ON COLUMN core.executable_version.capability_type_code IS
'What the version does — classification/extraction/etc.; may change across versions. @status reference.capability_type';
COMMENT ON COLUMN core.executable_version.trust_level_code IS
'Trust classification governing how its outputs may be used. @status reference.trust_level';
COMMENT ON COLUMN core.executable_version.governance_tier_code IS
'Governance tier driving review and approval rigor. @status reference.governance_tier';
COMMENT ON COLUMN core.executable_version.data_classification_code IS
'Sensitivity class of the data it handles. @status reference.data_classification';
COMMENT ON COLUMN core.executable_version.inference_config_id IS
'The inference parameters for this version; the model itself is resolved separately via the reference chain (D10). @ref core.inference_config hard';
COMMENT ON COLUMN core.executable_version.input_schema IS
'Schema of the structured input payload.';
COMMENT ON COLUMN core.executable_version.output_schema IS
'Schema of the structured output payload.';
COMMENT ON COLUMN core.executable_version.valid_from IS
'Start of the SCD-2 validity window.';
COMMENT ON COLUMN core.executable_version.valid_to IS
'End of the SCD-2 validity window; the open row (2099-12-31) is the current version.';
COMMENT ON COLUMN core.executable_version.created_at IS
'When the version was created.';
COMMENT ON COLUMN core.executable_version.created_by_actor_id IS
'Who created it. @ref core.actor hard';
COMMENT ON COLUMN core.executable_version.created_role_code IS
'The capacity they acted in. @status reference.role';
