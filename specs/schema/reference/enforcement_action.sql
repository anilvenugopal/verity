-- reference.enforcement_action  ·  subject: compliance  ·  (table)

CREATE TABLE reference.enforcement_action (
    code text NOT NULL, label text NOT NULL, description text, sort_order integer NOT NULL,
    grouping text, parent_code text, effective_start_date date NOT NULL DEFAULT current_date,
    effective_end_date date NOT NULL DEFAULT '2099-12-31', is_active boolean NOT NULL DEFAULT true, metadata jsonb NOT NULL DEFAULT '{}'::jsonb,
    created_at timestamptz NOT NULL DEFAULT now(), updated_at timestamptz NOT NULL DEFAULT now(),
    CONSTRAINT pk_enforcement_action PRIMARY KEY (code), CONSTRAINT uq_enforcement_action_sort UNIQUE (sort_order));
INSERT INTO reference.enforcement_action (code, label, sort_order) VALUES
    ('block',1),('refuse',2),('suppress_write',3),('warn',4),('log_only',5);
COMMENT ON TABLE reference.enforcement_action IS
'What a control does when it fires (block/refuse/suppress_write/warn/log_only).

@lifecycle reference
@subject compliance';
