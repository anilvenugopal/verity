-- core.target_binding  ·  subject: registry  ·  (table)

CREATE TABLE core.target_binding (
    target_binding_id uuid NOT NULL DEFAULT uuidv7(), executable_version_id uuid NOT NULL,
    name text NOT NULL,
    target_kind_code text NOT NULL,                           -- storage_object|task_output|structured
    data_connector_version_id uuid,                           -- the storage backend (for storage_object)
    delivery_mode_code text NOT NULL DEFAULT 'write_file',    -- write_file (storage) | inline (structured)
    write_mode_code text,                                      -- create|overwrite|create_or_version
    media_type text,
    target_payload_field text,                                -- which output field this writes
    locator jsonb NOT NULL DEFAULT '{}'::jsonb,               -- path_template / naming (variable config)
    ordinal integer NOT NULL DEFAULT 1,
    CONSTRAINT pk_target_binding PRIMARY KEY (target_binding_id),
    CONSTRAINT fk_target_binding_version FOREIGN KEY (executable_version_id) REFERENCES core.executable_version (executable_version_id) ON DELETE CASCADE,
    CONSTRAINT fk_target_binding_kind FOREIGN KEY (target_kind_code) REFERENCES reference.target_kind (code),
    CONSTRAINT fk_target_binding_delivery FOREIGN KEY (delivery_mode_code) REFERENCES reference.binding_delivery_mode (code),
    CONSTRAINT fk_target_binding_write_mode FOREIGN KEY (write_mode_code) REFERENCES reference.write_mode (code),
    CONSTRAINT fk_target_binding_connector FOREIGN KEY (data_connector_version_id) REFERENCES core.data_connector_version (data_connector_version_id) ON DELETE RESTRICT,
    CONSTRAINT ck_target_binding_storage_needs_connector
        CHECK (target_kind_code <> 'storage_object' OR (data_connector_version_id IS NOT NULL AND write_mode_code IS NOT NULL)),
    CONSTRAINT uq_target_binding_name UNIQUE (executable_version_id, name));
COMMENT ON TABLE core.target_binding IS 'tier:1. Declarative OUTPUT written after the executable runs (v1 write_target renamed). Files-to-storage via connector + locator + write_mode. Uniform for agent+task. binding-grammar.';
