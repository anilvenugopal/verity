-- reference.command_kind  ·  subject: deploy  ·  (table)

CREATE TABLE reference.command_kind (
    code text NOT NULL, label text NOT NULL, description text, sort_order integer NOT NULL,
    grouping text, parent_code text, effective_start_date date NOT NULL DEFAULT current_date,
    effective_end_date date NOT NULL DEFAULT '2099-12-31', is_active boolean NOT NULL DEFAULT true, metadata jsonb NOT NULL DEFAULT '{}'::jsonb,
    created_at timestamptz NOT NULL DEFAULT now(), updated_at timestamptz NOT NULL DEFAULT now(),
    CONSTRAINT pk_command_kind PRIMARY KEY (code), CONSTRAINT uq_command_kind_sort UNIQUE (sort_order));

COMMENT ON TABLE reference.command_kind IS
'The kind of portal->agent harness command (patch/drain/deploy_package/...), used by harness_instance_command.

@lifecycle reference
@subject deploy';
