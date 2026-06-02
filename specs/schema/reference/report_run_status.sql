-- reference.report_run_status  ·  subject: reporting  ·  (table)

CREATE TABLE reference.report_run_status (
    code text NOT NULL, label text NOT NULL, description text, sort_order integer NOT NULL,
    grouping text, parent_code text, effective_start_date date NOT NULL DEFAULT current_date,
    effective_end_date date, is_active boolean NOT NULL DEFAULT true, metadata jsonb NOT NULL DEFAULT '{}'::jsonb,
    created_at timestamptz NOT NULL DEFAULT now(), updated_at timestamptz NOT NULL DEFAULT now(),
    CONSTRAINT pk_report_run_status PRIMARY KEY (code), CONSTRAINT uq_report_run_status_sort UNIQUE (sort_order));
INSERT INTO reference.report_run_status (code, label, sort_order) VALUES ('pending',1),('succeeded',2),('failed',3);
