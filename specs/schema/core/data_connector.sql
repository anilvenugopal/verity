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
COMMENT ON TABLE core.data_connector IS 'tier:1 component. A configured connection to a storage/data backend (connector_type). Backend config (bucket/container/base path/auth ref) in the connector version. Source/Target bindings resolve files THROUGH a connector.';
