-- reference.validation_run_status  ·  subject: validation  ·  (table)

CREATE TABLE reference.validation_run_status (code text NOT NULL, label text NOT NULL, description text, sort_order integer NOT NULL, grouping text, parent_code text, effective_start_date date NOT NULL DEFAULT current_date, effective_end_date date NOT NULL DEFAULT '2099-12-31', is_active boolean NOT NULL DEFAULT true, metadata jsonb NOT NULL DEFAULT '{}'::jsonb, created_at timestamptz NOT NULL DEFAULT now(), updated_at timestamptz NOT NULL DEFAULT now(), CONSTRAINT pk_validation_run_status PRIMARY KEY (code), CONSTRAINT uq_validation_run_status_sort UNIQUE (sort_order));

COMMENT ON TABLE reference.validation_run_status IS
'Status of a validation run (running/complete/failed).

@lifecycle reference
@subject validation';
