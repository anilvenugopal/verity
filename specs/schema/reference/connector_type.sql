-- reference.connector_type  ·  subject: registry  ·  (table)

-- connector_type: the storage/data backend a connector talks to (extensible).
CREATE TABLE reference.connector_type (
    code text NOT NULL, label text NOT NULL, description text, sort_order integer NOT NULL,
    grouping text, parent_code text, effective_start_date date NOT NULL DEFAULT current_date,
    effective_end_date date NOT NULL DEFAULT '2099-12-31', is_active boolean NOT NULL DEFAULT true, metadata jsonb NOT NULL DEFAULT '{}'::jsonb,
    created_at timestamptz NOT NULL DEFAULT now(), updated_at timestamptz NOT NULL DEFAULT now(),
    CONSTRAINT pk_connector_type PRIMARY KEY (code), CONSTRAINT uq_connector_type_sort UNIQUE (sort_order));
INSERT INTO reference.connector_type (code, label, sort_order, grouping) VALUES
    ('vault','Verity Vault',1,'object_store'),('s3','AWS S3',2,'object_store'),
    ('azure_blob','Azure Blob',3,'object_store'),('gcs','Google Cloud Storage',4,'object_store'),
    ('sharepoint','SharePoint',5,'document'),('filesystem','Filesystem',6,'file'),
    ('http','HTTP/URL',7,'web'),('database','Database',8,'database');
COMMENT ON TABLE reference.connector_type IS
'The storage/data backend a data_connector talks to (vault/s3/sharepoint/...); Source/Target bindings resolve through one.

@lifecycle reference
@subject registry';
