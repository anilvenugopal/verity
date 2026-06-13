-- reference.deployment_status  ·  subject: deploy  ·  (table)

CREATE TABLE reference.deployment_status (
    code text NOT NULL, label text NOT NULL, description text, sort_order integer NOT NULL,
    grouping text, parent_code text, effective_start_date date NOT NULL DEFAULT current_date,
    effective_end_date date NOT NULL DEFAULT '2099-12-31', is_active boolean NOT NULL DEFAULT true, metadata jsonb NOT NULL DEFAULT '{}'::jsonb,
    created_at timestamptz NOT NULL DEFAULT now(), updated_at timestamptz NOT NULL DEFAULT now(),
    CONSTRAINT pk_deployment_status PRIMARY KEY (code), CONSTRAINT uq_deployment_status_sort UNIQUE (sort_order));

COMMENT ON TABLE reference.deployment_status IS
'State of a deployment (active/superseded/stopped).

@lifecycle reference
@subject deploy';
