-- reference.command_kind  ·  subject: deploy  ·  (table)

CREATE TABLE reference.command_kind (
    code text NOT NULL, label text NOT NULL, description text, sort_order integer NOT NULL,
    grouping text, parent_code text, effective_start_date date NOT NULL DEFAULT current_date,
    effective_end_date date, is_active boolean NOT NULL DEFAULT true, metadata jsonb NOT NULL DEFAULT '{}'::jsonb,
    created_at timestamptz NOT NULL DEFAULT now(), updated_at timestamptz NOT NULL DEFAULT now(),
    CONSTRAINT pk_command_kind PRIMARY KEY (code), CONSTRAINT uq_command_kind_sort UNIQUE (sort_order));
INSERT INTO reference.command_kind (code, label, sort_order) VALUES
    ('patch',1),('restart',2),('drain',3),('enable',4),('disable',5),('reload_packages',6),('collect_diagnostics',7);
