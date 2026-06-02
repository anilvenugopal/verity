-- reference.quota_scope_type  ·  subject: runs  ·  (table)

CREATE TABLE reference.quota_scope_type (
    code text NOT NULL, label text NOT NULL, description text, sort_order integer NOT NULL,
    grouping text, parent_code text, effective_start_date date NOT NULL DEFAULT current_date,
    effective_end_date date, is_active boolean NOT NULL DEFAULT true, metadata jsonb NOT NULL DEFAULT '{}'::jsonb,
    created_at timestamptz NOT NULL DEFAULT now(), updated_at timestamptz NOT NULL DEFAULT now(),
    CONSTRAINT pk_quota_scope_type PRIMARY KEY (code), CONSTRAINT uq_quota_scope_type_sort UNIQUE (sort_order));
INSERT INTO reference.quota_scope_type (code, label, sort_order) VALUES
    ('application',1),('agent',2),('task',3),('model',4);
