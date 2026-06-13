-- reference.requirement_status  ·  subject: intake  ·  (table)

CREATE TABLE reference.requirement_status (
    code text NOT NULL, label text NOT NULL, description text, sort_order integer NOT NULL,
    grouping text, parent_code text, effective_start_date date NOT NULL DEFAULT current_date,
    effective_end_date date NOT NULL DEFAULT '2099-12-31', is_active boolean NOT NULL DEFAULT true, metadata jsonb NOT NULL DEFAULT '{}'::jsonb,
    created_at timestamptz NOT NULL DEFAULT now(), updated_at timestamptz NOT NULL DEFAULT now(),
    CONSTRAINT pk_requirement_status PRIMARY KEY (code), CONSTRAINT uq_requirement_status_sort UNIQUE (sort_order));

COMMENT ON TABLE reference.requirement_status IS
'Mutable status of an intake requirement (draft/...).

@lifecycle reference
@subject intake';
