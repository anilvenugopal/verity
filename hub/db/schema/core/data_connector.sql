-- core.data_connector  ·  subject: registry  ·  (table)

-- data_connector
CREATE TABLE core.data_connector (
    data_connector_id uuid NOT NULL DEFAULT uuidv7(), name text NOT NULL,
    connector_type_code text NOT NULL,                       -- vault|s3|azure_blob|gcs|sharepoint|filesystem|http|database
    description text, created_at timestamptz NOT NULL DEFAULT now(), updated_at timestamptz NOT NULL DEFAULT now(),
    created_by_actor_id uuid NOT NULL, created_role_code text NOT NULL,
    CONSTRAINT pk_data_connector PRIMARY KEY (data_connector_id),
    CONSTRAINT fk_data_connector_type FOREIGN KEY (connector_type_code) REFERENCES reference.connector_type (code),
    CONSTRAINT fk_data_connector_created_by FOREIGN KEY (created_by_actor_id) REFERENCES core.actor (actor_id),
    CONSTRAINT fk_data_connector_created_role FOREIGN KEY (created_role_code) REFERENCES reference.role (code),
    CONSTRAINT uq_data_connector_name UNIQUE (name));
COMMENT ON TABLE core.data_connector IS
'A configured connection to a storage or data backend (connector_type). The backend config — bucket/container/base path/auth ref — lives in the connector version; Source and Target bindings resolve files THROUGH a connector rather than hard-coding a backend.

@tier 1
@lifecycle mutable
@subject registry
@status reference.connector_type
@decision D5';
COMMENT ON COLUMN core.data_connector.data_connector_id IS
'Identity of the connector.';
COMMENT ON COLUMN core.data_connector.name IS
'Human name; unique.';
COMMENT ON COLUMN core.data_connector.connector_type_code IS
'Which backend kind it talks to (vault/s3/sharepoint/...). @status reference.connector_type';
COMMENT ON COLUMN core.data_connector.description IS
'What the connector is for.';
COMMENT ON COLUMN core.data_connector.created_at IS
'When created.';
COMMENT ON COLUMN core.data_connector.updated_at IS
'When last updated.';
COMMENT ON COLUMN core.data_connector.created_by_actor_id IS
'Who created it. @ref core.actor hard';
COMMENT ON COLUMN core.data_connector.created_role_code IS
'The capacity they acted in. @status reference.role';
