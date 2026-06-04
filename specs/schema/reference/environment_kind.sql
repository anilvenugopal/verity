-- reference.environment_kind  ·  subject: deploy  ·  (table)

CREATE TABLE reference.environment_kind (
    code text NOT NULL, label text NOT NULL, description text, sort_order integer NOT NULL,
    grouping text, parent_code text, effective_start_date date NOT NULL DEFAULT current_date,
    effective_end_date date NOT NULL DEFAULT '2099-12-31', is_active boolean NOT NULL DEFAULT true, metadata jsonb NOT NULL DEFAULT '{}'::jsonb,
    created_at timestamptz NOT NULL DEFAULT now(), updated_at timestamptz NOT NULL DEFAULT now(),
    CONSTRAINT pk_environment_kind PRIMARY KEY (code), CONSTRAINT uq_environment_kind_sort UNIQUE (sort_order));
INSERT INTO reference.environment_kind (code, label, sort_order) VALUES ('non_prod','Non Prod',1),('prod','Prod',2),('ephemeral','Ephemeral',3);
COMMENT ON TABLE reference.environment_kind IS
'The class of a deployment environment (non_prod/prod/ephemeral) that gates allowed run-modes.

@lifecycle reference
@subject deploy';
