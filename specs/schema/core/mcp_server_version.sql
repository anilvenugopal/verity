-- core.mcp_server_version  ·  subject: registry  ·  (table)

CREATE TABLE core.mcp_server_version (
    mcp_server_version_id uuid NOT NULL DEFAULT uuidv7(), mcp_server_id uuid NOT NULL, semver text NOT NULL,
    config jsonb NOT NULL DEFAULT '{}'::jsonb, valid_from timestamptz, valid_to timestamptz,
    created_at timestamptz NOT NULL DEFAULT now(), created_by_actor_id uuid NOT NULL, created_role_code text NOT NULL,
    CONSTRAINT pk_mcp_server_version PRIMARY KEY (mcp_server_version_id),
    CONSTRAINT fk_mcp_server_version_server FOREIGN KEY (mcp_server_id) REFERENCES core.mcp_server (mcp_server_id) ON DELETE RESTRICT,
    CONSTRAINT uq_mcp_server_version_semver UNIQUE (mcp_server_id, semver));
