-- reference.deployment_operation  ·  subject: deploy  ·  (table)

CREATE TABLE reference.deployment_operation (
    code text NOT NULL, label text NOT NULL, description text, sort_order integer NOT NULL,
    grouping text, parent_code text, effective_start_date date NOT NULL DEFAULT current_date,
    effective_end_date date, is_active boolean NOT NULL DEFAULT true, metadata jsonb NOT NULL DEFAULT '{}'::jsonb,
    created_at timestamptz NOT NULL DEFAULT now(), updated_at timestamptz NOT NULL DEFAULT now(),
    CONSTRAINT pk_deployment_operation PRIMARY KEY (code), CONSTRAINT uq_deployment_operation_sort UNIQUE (sort_order));
INSERT INTO reference.deployment_operation (code, label, sort_order) VALUES
    ('deploy_nonprod',1),('deploy_prod',2),('promote_champion',3),('lock_deprecated',4),('cleanup_deprecated',5),('rollback',6);
