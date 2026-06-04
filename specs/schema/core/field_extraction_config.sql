-- core.field_extraction_config  ·  subject: validation  ·  (table)

CREATE TABLE core.field_extraction_config (
    field_extraction_config_id uuid NOT NULL DEFAULT uuidv7(), executable_version_id uuid NOT NULL,
    field_name text NOT NULL, extraction_field_type_code text NOT NULL, extraction_match_type_code text NOT NULL,
    tolerance numeric(8,4), tolerance_unit_code text, created_at timestamptz NOT NULL DEFAULT now(),
    CONSTRAINT pk_field_extraction_config PRIMARY KEY (field_extraction_config_id),
    CONSTRAINT fk_fec_version FOREIGN KEY (executable_version_id) REFERENCES core.executable_version (executable_version_id) ON DELETE CASCADE,
    CONSTRAINT fk_fec_field_type FOREIGN KEY (extraction_field_type_code) REFERENCES reference.extraction_field_type (code),
    CONSTRAINT fk_fec_match_type FOREIGN KEY (extraction_match_type_code) REFERENCES reference.extraction_match_type (code),
    CONSTRAINT fk_fec_tolerance_unit FOREIGN KEY (tolerance_unit_code) REFERENCES reference.tolerance_unit (code));
COMMENT ON TABLE core.field_extraction_config IS
'Per-field grading config for an extraction executable: how each output field is typed and matched, with an optional tolerance and unit. Drives field-level validation of extraction outputs (C9).

@tier 1
@lifecycle mutable
@subject validation
@status reference.extraction_field_type
@status reference.extraction_match_type';
COMMENT ON COLUMN core.field_extraction_config.field_extraction_config_id IS
'Identity of the config.';
COMMENT ON COLUMN core.field_extraction_config.executable_version_id IS
'The version this configures. @ref core.executable_version hard';
COMMENT ON COLUMN core.field_extraction_config.field_name IS
'The output field this configures.';
COMMENT ON COLUMN core.field_extraction_config.extraction_field_type_code IS
'Type of the field. @status reference.extraction_field_type';
COMMENT ON COLUMN core.field_extraction_config.extraction_match_type_code IS
'How the field is matched. @status reference.extraction_match_type';
COMMENT ON COLUMN core.field_extraction_config.tolerance IS
'Allowed tolerance for a near-match.';
COMMENT ON COLUMN core.field_extraction_config.tolerance_unit_code IS
'Unit of the tolerance. @status reference.tolerance_unit';
COMMENT ON COLUMN core.field_extraction_config.created_at IS
'When set.';
