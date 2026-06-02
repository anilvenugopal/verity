-- reference.control_type  ·  subject: compliance  ·  (table)

CREATE TABLE reference.control_type (
    code text NOT NULL, label text NOT NULL, description text, sort_order integer NOT NULL,
    grouping text, parent_code text, effective_start_date date NOT NULL DEFAULT current_date,
    effective_end_date date, is_active boolean NOT NULL DEFAULT true, metadata jsonb NOT NULL DEFAULT '{}'::jsonb,
    created_at timestamptz NOT NULL DEFAULT now(), updated_at timestamptz NOT NULL DEFAULT now(),
    CONSTRAINT pk_control_type PRIMARY KEY (code), CONSTRAINT uq_control_type_sort UNIQUE (sort_order));
INSERT INTO reference.control_type (code, label, sort_order) VALUES
    ('preventive',1),('detective',2),('corrective',3),('directive',4);
