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
