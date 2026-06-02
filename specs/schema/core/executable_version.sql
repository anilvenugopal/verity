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
    valid_from            timestamptz,                          -- SCD-2 temporal window
    valid_to              timestamptz,
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
COMMENT ON TABLE core.executable_version IS 'tier:1 immutable SCD-2 version of an executable (valid_from/valid_to). Lifecycle/champion/bindings/deployment all reference THIS. kind_code denormalized to enforce agent-only component rules. D5.';
CREATE INDEX ix_executable_version_executable ON core.executable_version (executable_id);
