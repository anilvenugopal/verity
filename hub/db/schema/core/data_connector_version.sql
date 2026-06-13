-- core.data_connector_version  ·  subject: registry  ·  (table)

CREATE TABLE core.data_connector_version (
    data_connector_version_id uuid NOT NULL DEFAULT uuidv7(), data_connector_id uuid NOT NULL, semver text NOT NULL,
    config jsonb NOT NULL DEFAULT '{}'::jsonb, valid_from timestamptz NOT NULL DEFAULT now(), valid_to timestamptz NOT NULL DEFAULT '2099-12-31 00:00:00+00',
    created_at timestamptz NOT NULL DEFAULT now(), created_by_actor_id uuid NOT NULL, created_role_code text NOT NULL,
    CONSTRAINT pk_data_connector_version PRIMARY KEY (data_connector_version_id),
    CONSTRAINT fk_data_connector_version_connector FOREIGN KEY (data_connector_id) REFERENCES core.data_connector (data_connector_id) ON DELETE RESTRICT,
    CONSTRAINT uq_data_connector_version_semver UNIQUE (data_connector_id, semver));
COMMENT ON TABLE core.data_connector_version IS
'An immutable version of a connector''s backend configuration (bucket, base path, auth reference), pinned so a deployment and its runs resolve storage exactly as configured. deployment_connection binds these per environment.

@tier 1
@lifecycle scd2
@subject registry
@decision D5';
COMMENT ON COLUMN core.data_connector_version.data_connector_version_id IS
'Identity of the connector version.';
COMMENT ON COLUMN core.data_connector_version.data_connector_id IS
'The connector this versions. @ref core.data_connector hard';
COMMENT ON COLUMN core.data_connector_version.semver IS
'Semantic version within the connector; unique per connector.';
COMMENT ON COLUMN core.data_connector_version.config IS
'Backend configuration (bucket/path/auth ref) for this version.';
COMMENT ON COLUMN core.data_connector_version.valid_from IS
'Start of the SCD-2 validity window.';
COMMENT ON COLUMN core.data_connector_version.valid_to IS
'End of the window; the open row (2099-12-31) is current.';
COMMENT ON COLUMN core.data_connector_version.created_at IS
'When created.';
COMMENT ON COLUMN core.data_connector_version.created_by_actor_id IS
'Who created it. @ref core.actor hard';
COMMENT ON COLUMN core.data_connector_version.created_role_code IS
'The capacity they acted in. @status reference.role';
