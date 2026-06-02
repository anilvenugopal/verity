-- reference.run_purpose  ·  subject: runs  ·  (table)

-- (run_status, run_completion_status, run_entity_kind, outbox_status stay NATIVE enums
--  per D1 — hot-path dispatch state; declared in 07-runs.)
CREATE TABLE reference.run_purpose (
    code text NOT NULL, label text NOT NULL, description text, sort_order integer NOT NULL,
    grouping text, parent_code text, effective_start_date date NOT NULL DEFAULT current_date,
    effective_end_date date, is_active boolean NOT NULL DEFAULT true, metadata jsonb NOT NULL DEFAULT '{}'::jsonb,
    created_at timestamptz NOT NULL DEFAULT now(), updated_at timestamptz NOT NULL DEFAULT now(),
    CONSTRAINT pk_run_purpose PRIMARY KEY (code), CONSTRAINT uq_run_purpose_sort UNIQUE (sort_order));
INSERT INTO reference.run_purpose (code, label, sort_order) VALUES
    ('production',1),('test',2),('validation',3),('audit_rerun',4);
