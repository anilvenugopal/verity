-- core.mcp_server_version  ·  subject: registry  ·  (table)

CREATE TABLE core.mcp_server_version (
    mcp_server_version_id uuid NOT NULL DEFAULT uuidv7(), mcp_server_id uuid NOT NULL, semver text NOT NULL,
    config jsonb NOT NULL DEFAULT '{}'::jsonb, valid_from timestamptz NOT NULL DEFAULT now(), valid_to timestamptz NOT NULL DEFAULT '2099-12-31 00:00:00+00',
    created_at timestamptz NOT NULL DEFAULT now(), created_by_actor_id uuid NOT NULL, created_role_code text NOT NULL,
    CONSTRAINT pk_mcp_server_version PRIMARY KEY (mcp_server_version_id),
    CONSTRAINT fk_mcp_server_version_server FOREIGN KEY (mcp_server_id) REFERENCES core.mcp_server (mcp_server_id) ON DELETE RESTRICT,
    CONSTRAINT uq_mcp_server_version_semver UNIQUE (mcp_server_id, semver));
COMMENT ON TABLE core.mcp_server_version IS
'An immutable version of an MCP server''s config, pinned for reproducible agent runs (D5).

@tier 1
@lifecycle scd2
@subject registry
@decision D5';
COMMENT ON COLUMN core.mcp_server_version.mcp_server_version_id IS
'Identity of the MCP server version.';
COMMENT ON COLUMN core.mcp_server_version.mcp_server_id IS
'The server this versions. @ref core.mcp_server hard';
COMMENT ON COLUMN core.mcp_server_version.semver IS
'Semantic version within the server; unique per server.';
COMMENT ON COLUMN core.mcp_server_version.config IS
'Server configuration for this version.';
COMMENT ON COLUMN core.mcp_server_version.valid_from IS
'Start of the SCD-2 validity window.';
COMMENT ON COLUMN core.mcp_server_version.valid_to IS
'End of the window; the open row (2099-12-31) is current.';
COMMENT ON COLUMN core.mcp_server_version.created_at IS
'When created.';
COMMENT ON COLUMN core.mcp_server_version.created_by_actor_id IS
'Who created it. @ref core.actor hard';
COMMENT ON COLUMN core.mcp_server_version.created_role_code IS
'The capacity they acted in. @status reference.role';
