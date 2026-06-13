-- core.executable_mcp_assignment  ·  subject: registry  ·  (table)

-- MCP: AGENT-ONLY (same enforcement).
CREATE TABLE core.executable_mcp_assignment (
    executable_version_id uuid NOT NULL, mcp_server_version_id uuid NOT NULL,
    executable_kind_code text NOT NULL,
    CONSTRAINT pk_executable_mcp_assignment PRIMARY KEY (executable_version_id, mcp_server_version_id),
    CONSTRAINT fk_ema_executable_version FOREIGN KEY (executable_version_id, executable_kind_code)
        REFERENCES core.executable_version (executable_version_id, kind_code) ON DELETE CASCADE,
    CONSTRAINT fk_ema_mcp_version FOREIGN KEY (mcp_server_version_id) REFERENCES core.mcp_server_version (mcp_server_version_id) ON DELETE RESTRICT,
    CONSTRAINT ck_ema_agent_only CHECK (executable_kind_code = 'agent'));
COMMENT ON TABLE core.executable_mcp_assignment IS
'Attaches an mcp_server_version to an AGENT version, with the same agent-only enforcement as tools (composite FK + CHECK kind=agent) (D5, binding-grammar).

@tier 1
@lifecycle mutable
@subject registry
@invariant agent-only, enforced by composite FK + CHECK
@decision D5';
COMMENT ON COLUMN core.executable_mcp_assignment.executable_version_id IS
'The agent version using the MCP server. @ref core.executable_version hard';
COMMENT ON COLUMN core.executable_mcp_assignment.mcp_server_version_id IS
'The exact MCP server version pinned. @ref core.mcp_server_version hard';
COMMENT ON COLUMN core.executable_mcp_assignment.executable_kind_code IS
'Must be agent; the composite FK + CHECK is what enforces agent-only.';
