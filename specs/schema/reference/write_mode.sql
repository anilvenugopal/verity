-- reference.write_mode  ·  subject: registry  ·  (table)

-- write_mode: how a target write places the object.
CREATE TABLE reference.write_mode (
    code text NOT NULL, label text NOT NULL, description text, sort_order integer NOT NULL,
    grouping text, parent_code text, effective_start_date date NOT NULL DEFAULT current_date,
    effective_end_date date, is_active boolean NOT NULL DEFAULT true, metadata jsonb NOT NULL DEFAULT '{}'::jsonb,
    created_at timestamptz NOT NULL DEFAULT now(), updated_at timestamptz NOT NULL DEFAULT now(),
    CONSTRAINT pk_write_mode PRIMARY KEY (code), CONSTRAINT uq_write_mode_sort UNIQUE (sort_order));
INSERT INTO reference.write_mode (code, label, sort_order) VALUES
    ('create',1),('overwrite',2),('create_or_version',3);
