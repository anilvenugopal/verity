-- reference.deployment_operation  ·  subject: deploy  ·  (table)

CREATE TABLE reference.deployment_operation (
    code text NOT NULL, label text NOT NULL, description text, sort_order integer NOT NULL,
    grouping text, parent_code text, effective_start_date date NOT NULL DEFAULT current_date,
    effective_end_date date NOT NULL DEFAULT '2099-12-31', is_active boolean NOT NULL DEFAULT true, metadata jsonb NOT NULL DEFAULT '{}'::jsonb,
    created_at timestamptz NOT NULL DEFAULT now(), updated_at timestamptz NOT NULL DEFAULT now(),
    CONSTRAINT pk_deployment_operation PRIMARY KEY (code), CONSTRAINT uq_deployment_operation_sort UNIQUE (sort_order));

COMMENT ON TABLE reference.deployment_operation IS
'A governed deployment operation (deploy_*/promote_champion/lock_deprecated/cleanup_deprecated/rollback), recorded in deployment_event.

@lifecycle reference
@subject deploy';
