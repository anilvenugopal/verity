-- reference.run_status  ·  subject: runs  ·  (table)

-- Event-sourced run state (one row per execution_run_status transition).
-- Converted from a native enum to reference vocab per the all-status-fields standard.
CREATE TABLE reference.run_status (
    code text NOT NULL, label text NOT NULL, description text, sort_order integer NOT NULL,
    grouping text, parent_code text, effective_start_date date NOT NULL DEFAULT current_date,
    effective_end_date date NOT NULL DEFAULT '2099-12-31', is_active boolean NOT NULL DEFAULT true, metadata jsonb NOT NULL DEFAULT '{}'::jsonb,
    created_at timestamptz NOT NULL DEFAULT now(), updated_at timestamptz NOT NULL DEFAULT now(),
    CONSTRAINT pk_run_status PRIMARY KEY (code), CONSTRAINT uq_run_status_sort UNIQUE (sort_order));

COMMENT ON TABLE reference.run_status IS
'Event-sourced run state, one row per execution_run_status transition (submitted/claimed/heartbeat/released).

@lifecycle reference
@subject runs';
