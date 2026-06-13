-- reference.connector_type  ·  subject: registry  ·  (table)

-- connector_type: the storage/data backend a connector talks to (extensible).
CREATE TABLE reference.connector_type (
    code text NOT NULL, label text NOT NULL, description text, sort_order integer NOT NULL,
    grouping text, parent_code text, effective_start_date date NOT NULL DEFAULT current_date,
    effective_end_date date NOT NULL DEFAULT '2099-12-31', is_active boolean NOT NULL DEFAULT true, metadata jsonb NOT NULL DEFAULT '{}'::jsonb,
    created_at timestamptz NOT NULL DEFAULT now(), updated_at timestamptz NOT NULL DEFAULT now(),
    CONSTRAINT pk_connector_type PRIMARY KEY (code), CONSTRAINT uq_connector_type_sort UNIQUE (sort_order));

COMMENT ON TABLE reference.connector_type IS
'The storage/data backend a data_connector talks to (vault/s3/sharepoint/...); Source/Target bindings resolve through one.

@lifecycle reference
@subject registry';
