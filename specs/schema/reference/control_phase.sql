-- reference.control_phase  ·  subject: compliance  ·  (table)

CREATE TABLE reference.control_phase (
    code text NOT NULL, label text NOT NULL, description text, sort_order integer NOT NULL,
    grouping text, parent_code text, effective_start_date date NOT NULL DEFAULT current_date,
    effective_end_date date NOT NULL DEFAULT '2099-12-31', is_active boolean NOT NULL DEFAULT true, metadata jsonb NOT NULL DEFAULT '{}'::jsonb,
    created_at timestamptz NOT NULL DEFAULT now(), updated_at timestamptz NOT NULL DEFAULT now(),
    CONSTRAINT pk_control_phase PRIMARY KEY (code), CONSTRAINT uq_control_phase_sort UNIQUE (sort_order));

COMMENT ON TABLE reference.control_phase IS
'The lifecycle phase a compliance control acts at (design_time/deploy_time/static_model/execution).

@lifecycle reference
@subject compliance';
