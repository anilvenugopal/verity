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
