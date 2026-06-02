-- reference.report_kind  ·  subject: reporting  ·  (table)

CREATE TABLE reference.report_kind (
    code text NOT NULL, label text NOT NULL, description text, sort_order integer NOT NULL,
    grouping text, parent_code text, effective_start_date date NOT NULL DEFAULT current_date,
    effective_end_date date, is_active boolean NOT NULL DEFAULT true, metadata jsonb NOT NULL DEFAULT '{}'::jsonb,
    created_at timestamptz NOT NULL DEFAULT now(), updated_at timestamptz NOT NULL DEFAULT now(),
    CONSTRAINT pk_report_kind PRIMARY KEY (code), CONSTRAINT uq_report_kind_sort UNIQUE (sort_order));
INSERT INTO reference.report_kind (code, label, sort_order) VALUES ('metadata_driven',1),('template_driven',2);
