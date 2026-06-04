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
COMMENT ON TABLE core.target_binding IS
'A declarative OUTPUT written after the executable runs — uniform for agents and tasks. Files to storage go THROUGH a connector via a locator and a write_mode (create/overwrite/create_or_version). A storage_object target must name both a connector and a write_mode (CHECK). NOTE: a shadow run suppresses all target writes regardless of these rows (the shadow safety rail).

@tier 1
@lifecycle mutable
@subject registry
@status reference.target_kind
@status reference.binding_delivery_mode
@status reference.write_mode
@see binding-grammar';
COMMENT ON COLUMN core.target_binding.target_binding_id IS
'Identity of the binding.';
COMMENT ON COLUMN core.target_binding.executable_version_id IS
'The version this output belongs to. @ref core.executable_version hard';
COMMENT ON COLUMN core.target_binding.name IS
'Binding name; unique within the version.';
COMMENT ON COLUMN core.target_binding.target_kind_code IS
'Where the output goes — storage_object/task_output/structured. @status reference.target_kind';
COMMENT ON COLUMN core.target_binding.data_connector_version_id IS
'The storage backend for a storage_object target; required for that kind (CHECK). @ref core.data_connector_version hard';
COMMENT ON COLUMN core.target_binding.delivery_mode_code IS
'How the output is delivered — write_file for storage, inline for structured. @status reference.binding_delivery_mode';
COMMENT ON COLUMN core.target_binding.write_mode_code IS
'create/overwrite/create_or_version; required for a storage_object target (CHECK). @status reference.write_mode';
COMMENT ON COLUMN core.target_binding.media_type IS
'Media type of the written output.';
COMMENT ON COLUMN core.target_binding.target_payload_field IS
'Which output field this binding writes.';
COMMENT ON COLUMN core.target_binding.locator IS
'Variable config for the write — path template, naming.';
COMMENT ON COLUMN core.target_binding.ordinal IS
'Order among the versions outputs.';
