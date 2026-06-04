-- reference.intake_status  ·  subject: intake  ·  (table)

CREATE TABLE reference.intake_status (
    code text NOT NULL, label text NOT NULL, description text, sort_order integer NOT NULL,
    grouping text, parent_code text, effective_start_date date NOT NULL DEFAULT current_date,
    effective_end_date date NOT NULL DEFAULT '2099-12-31', is_active boolean NOT NULL DEFAULT true, metadata jsonb NOT NULL DEFAULT '{}'::jsonb,
    created_at timestamptz NOT NULL DEFAULT now(), updated_at timestamptz NOT NULL DEFAULT now(),
    CONSTRAINT pk_intake_status PRIMARY KEY (code), CONSTRAINT uq_intake_status_sort UNIQUE (sort_order));

COMMENT ON TABLE reference.intake_status IS
'Lifecycle status of an intake use-case (proposed/...).

@lifecycle reference
@subject intake';
