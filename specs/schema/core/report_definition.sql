-- core.report_definition  ·  subject: reporting  ·  (table)

CREATE TABLE core.report_definition (
    report_definition_id uuid        NOT NULL DEFAULT uuidv7(),
    name                 text        NOT NULL,
    report_kind_code     text        NOT NULL,                  -- metadata_driven | template_driven
    description          text,
    sql_template         text,                                   -- for template_driven
    spec                 jsonb       NOT NULL DEFAULT '{}'::jsonb,-- for metadata_driven (fields, filters, grouping)
    created_at           timestamptz  NOT NULL DEFAULT now(),
    updated_at           timestamptz  NOT NULL DEFAULT now(),
    created_by_actor_id  uuid        NOT NULL,
    created_role_code    text        NOT NULL,
    CONSTRAINT pk_report_definition PRIMARY KEY (report_definition_id),
    CONSTRAINT fk_report_definition_kind FOREIGN KEY (report_kind_code) REFERENCES reference.report_kind (code),
    CONSTRAINT fk_report_definition_created_by FOREIGN KEY (created_by_actor_id) REFERENCES core.actor (actor_id),
    CONSTRAINT fk_report_definition_created_role FOREIGN KEY (created_role_code) REFERENCES reference.role (code),
    CONSTRAINT uq_report_definition_name UNIQUE (name),
    CONSTRAINT ck_report_definition_template CHECK (report_kind_code <> 'template_driven' OR sql_template IS NOT NULL));
COMMENT ON TABLE core.report_definition IS
'A report definition — metadata-driven (fields/filters/grouping in spec) or template-driven (a sql_template). Reports run as ASYNC jobs against the analytics tier, never on the status path; the canonical analytics store is external (Iceberg/Parquet), so these rows are definitions, not the data (ADR-0007).

@tier 1
@lifecycle mutable
@subject reporting
@status reference.report_kind
@adr 0007';
COMMENT ON COLUMN core.report_definition.report_definition_id IS
'Identity of the report.';
COMMENT ON COLUMN core.report_definition.name IS
'Report name; unique.';
COMMENT ON COLUMN core.report_definition.report_kind_code IS
'metadata_driven or template_driven. @status reference.report_kind';
COMMENT ON COLUMN core.report_definition.description IS
'What the report shows.';
COMMENT ON COLUMN core.report_definition.sql_template IS
'The SQL for a template_driven report; required for that kind (CHECK).';
COMMENT ON COLUMN core.report_definition.spec IS
'Field/filter/grouping spec for a metadata_driven report.';
COMMENT ON COLUMN core.report_definition.created_at IS
'When created.';
COMMENT ON COLUMN core.report_definition.updated_at IS
'When last updated.';
COMMENT ON COLUMN core.report_definition.created_by_actor_id IS
'Who created it. @ref core.actor hard';
COMMENT ON COLUMN core.report_definition.created_role_code IS
'The capacity they acted in. @status reference.role';
