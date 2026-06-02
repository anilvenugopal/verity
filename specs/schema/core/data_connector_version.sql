-- core.data_connector_version  ·  subject: registry  ·  (table)

CREATE TABLE core.data_connector_version (
    data_connector_version_id uuid NOT NULL DEFAULT uuidv7(), data_connector_id uuid NOT NULL, semver text NOT NULL,
    config jsonb NOT NULL DEFAULT '{}'::jsonb, valid_from timestamptz, valid_to timestamptz,
    created_at timestamptz NOT NULL DEFAULT now(), created_by_actor_id uuid NOT NULL, created_role_code text NOT NULL,
    CONSTRAINT pk_data_connector_version PRIMARY KEY (data_connector_version_id),
    CONSTRAINT fk_data_connector_version_connector FOREIGN KEY (data_connector_id) REFERENCES core.data_connector (data_connector_id) ON DELETE RESTRICT,
    CONSTRAINT uq_data_connector_version_semver UNIQUE (data_connector_id, semver));
