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
COMMENT ON TABLE core.report_definition IS 'tier:1. A report definition (metadata- or template-driven). Reports run as async jobs against the analytics tier (ADR-0007), never on the status path.';
