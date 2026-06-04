-- reference.run_completion_status  ·  subject: runs  ·  (table)

-- Terminal completion outcome, set on the 'released' run_status event.
-- Converted from a native enum to reference vocab per the all-status-fields standard.
CREATE TABLE reference.run_completion_status (
    code text NOT NULL, label text NOT NULL, description text, sort_order integer NOT NULL,
    grouping text, parent_code text, effective_start_date date NOT NULL DEFAULT current_date,
    effective_end_date date NOT NULL DEFAULT '2099-12-31', is_active boolean NOT NULL DEFAULT true, metadata jsonb NOT NULL DEFAULT '{}'::jsonb,
    created_at timestamptz NOT NULL DEFAULT now(), updated_at timestamptz NOT NULL DEFAULT now(),
    CONSTRAINT pk_run_completion_status PRIMARY KEY (code), CONSTRAINT uq_run_completion_status_sort UNIQUE (sort_order));
INSERT INTO reference.run_completion_status (code, label, sort_order) VALUES
    ('complete',1),('cancelled',2),('errored',3);
COMMENT ON TABLE reference.run_completion_status IS
'Terminal completion outcome of a run, set on the released event (complete/cancelled/errored).

@lifecycle reference
@subject runs';
