-- core.source_binding  ·  subject: registry  ·  (table)

CREATE TABLE core.source_binding (
    source_binding_id uuid NOT NULL DEFAULT uuidv7(), executable_version_id uuid NOT NULL,
    name text NOT NULL,
    source_kind_code text NOT NULL,                           -- storage_object|task_output|structured|inline_content
    data_connector_version_id uuid,                           -- the storage backend (for storage_object)
    delivery_mode_code text NOT NULL DEFAULT 'inline',        -- inline|reference|download|extracted (the base64-only fix)
    media_type text,                                           -- e.g. application/pdf, text/csv
    locator jsonb NOT NULL DEFAULT '{}'::jsonb,               -- path_template / query / business_keys (variable config)
    nullable boolean NOT NULL DEFAULT false,                  -- input may be absent at run time
    ordinal integer NOT NULL DEFAULT 1,
    CONSTRAINT pk_source_binding PRIMARY KEY (source_binding_id),
    CONSTRAINT fk_source_binding_version FOREIGN KEY (executable_version_id) REFERENCES core.executable_version (executable_version_id) ON DELETE CASCADE,
    CONSTRAINT fk_source_binding_kind FOREIGN KEY (source_kind_code) REFERENCES reference.source_kind (code),
    CONSTRAINT fk_source_binding_delivery FOREIGN KEY (delivery_mode_code) REFERENCES reference.binding_delivery_mode (code),
    CONSTRAINT fk_source_binding_connector FOREIGN KEY (data_connector_version_id) REFERENCES core.data_connector_version (data_connector_version_id) ON DELETE RESTRICT,
    -- a storage_object must name its backend connector
    CONSTRAINT ck_source_binding_storage_needs_connector
        CHECK (source_kind_code <> 'storage_object' OR data_connector_version_id IS NOT NULL),
    CONSTRAINT uq_source_binding_name UNIQUE (executable_version_id, name));
COMMENT ON TABLE core.source_binding IS 'tier:1. Declarative INPUT resolved before the executable runs (v1 source_binding renamed). Files-from-storage via connector + locator + delivery_mode (inline/reference/download/extracted). Uniform for agent+task. binding-grammar.';
