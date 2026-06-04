-- reference.write_mode  ·  subject: registry  ·  (table)

-- write_mode: how a target write places the object.
CREATE TABLE reference.write_mode (
    code text NOT NULL, label text NOT NULL, description text, sort_order integer NOT NULL,
    grouping text, parent_code text, effective_start_date date NOT NULL DEFAULT current_date,
    effective_end_date date NOT NULL DEFAULT '2099-12-31', is_active boolean NOT NULL DEFAULT true, metadata jsonb NOT NULL DEFAULT '{}'::jsonb,
    created_at timestamptz NOT NULL DEFAULT now(), updated_at timestamptz NOT NULL DEFAULT now(),
    CONSTRAINT pk_write_mode PRIMARY KEY (code), CONSTRAINT uq_write_mode_sort UNIQUE (sort_order));
INSERT INTO reference.write_mode (code, label, sort_order) VALUES
    ('create','Create',1),('overwrite','Overwrite',2),('create_or_version','Create Or Version',3);
COMMENT ON TABLE reference.write_mode IS
'How a Target Binding places the written object (create/overwrite/create_or_version).

@lifecycle reference
@subject registry';
