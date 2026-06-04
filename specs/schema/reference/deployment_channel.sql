-- reference.deployment_channel  ·  subject: deploy  ·  (table)

CREATE TABLE reference.deployment_channel (
    code text NOT NULL, label text NOT NULL, description text, sort_order integer NOT NULL,
    grouping text, parent_code text, effective_start_date date NOT NULL DEFAULT current_date,
    effective_end_date date NOT NULL DEFAULT '2099-12-31', is_active boolean NOT NULL DEFAULT true, metadata jsonb NOT NULL DEFAULT '{}'::jsonb,
    created_at timestamptz NOT NULL DEFAULT now(), updated_at timestamptz NOT NULL DEFAULT now(),
    CONSTRAINT pk_deployment_channel PRIMARY KEY (code), CONSTRAINT uq_deployment_channel_sort UNIQUE (sort_order));

COMMENT ON TABLE reference.deployment_channel IS
'The release channel a version is published on.

@lifecycle reference
@subject deploy';
