-- reference.deployment_run_mode  ·  subject: deploy  ·  (table)

-- deployment_run_mode: how a deployed package executes (the shadow/ab/live/locked clarification)
CREATE TABLE reference.deployment_run_mode (
    code text NOT NULL, label text NOT NULL, description text, sort_order integer NOT NULL,
    grouping text, parent_code text, effective_start_date date NOT NULL DEFAULT current_date,
    effective_end_date date NOT NULL DEFAULT '2099-12-31', is_active boolean NOT NULL DEFAULT true, metadata jsonb NOT NULL DEFAULT '{}'::jsonb,
    created_at timestamptz NOT NULL DEFAULT now(), updated_at timestamptz NOT NULL DEFAULT now(),
    CONSTRAINT pk_deployment_run_mode PRIMARY KEY (code), CONSTRAINT uq_deployment_run_mode_sort UNIQUE (sort_order));

COMMENT ON TABLE reference.deployment_run_mode IS
'How a deployed package executes (live/shadow/ab/locked) — the read-only / write-suppression axis.

@lifecycle reference
@subject deploy';
