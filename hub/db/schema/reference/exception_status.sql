-- reference.exception_status  ·  subject: compliance  ·  (table)

CREATE TABLE reference.exception_status (
    code text NOT NULL, label text NOT NULL, description text, sort_order integer NOT NULL,
    grouping text, parent_code text, effective_start_date date NOT NULL DEFAULT current_date,
    effective_end_date date NOT NULL DEFAULT '2099-12-31', is_active boolean NOT NULL DEFAULT true, metadata jsonb NOT NULL DEFAULT '{}'::jsonb,
    created_at timestamptz NOT NULL DEFAULT now(), updated_at timestamptz NOT NULL DEFAULT now(),
    CONSTRAINT pk_exception_status PRIMARY KEY (code), CONSTRAINT uq_exception_status_sort UNIQUE (sort_order));

COMMENT ON TABLE reference.exception_status IS
'Lifecycle status of a compliance_exception (requested/approved/...).

@lifecycle reference
@subject compliance';
