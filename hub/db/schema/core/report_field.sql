-- core.report_field  ·  subject: reporting  ·  (table)

CREATE TABLE core.report_field (
    report_field_id      uuid        NOT NULL DEFAULT uuidv7(),
    report_definition_id uuid        NOT NULL,
    field_name           text        NOT NULL,
    expression           text,
    ordinal              integer      NOT NULL DEFAULT 1,
    CONSTRAINT pk_report_field PRIMARY KEY (report_field_id),
    CONSTRAINT fk_report_field_definition FOREIGN KEY (report_definition_id) REFERENCES core.report_definition (report_definition_id) ON DELETE CASCADE,
    CONSTRAINT uq_report_field_name UNIQUE (report_definition_id, field_name));
COMMENT ON TABLE core.report_field IS
'A field in a metadata-driven report definition: a named output column with an optional expression and an ordering. Unique by name within the report.

@tier 1
@lifecycle mutable
@subject reporting';
COMMENT ON COLUMN core.report_field.report_field_id IS
'Identity of the field.';
COMMENT ON COLUMN core.report_field.report_definition_id IS
'The report this field belongs to. @ref core.report_definition hard';
COMMENT ON COLUMN core.report_field.field_name IS
'Output column name; unique within the report.';
COMMENT ON COLUMN core.report_field.expression IS
'Expression computing the field, when not a plain column.';
COMMENT ON COLUMN core.report_field.ordinal IS
'Column order in the output.';
