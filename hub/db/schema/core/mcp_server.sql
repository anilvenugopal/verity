-- core.mcp_server  ·  subject: registry  ·  (table)

-- mcp_server (agent-only at assignment time)
CREATE TABLE core.mcp_server (
    mcp_server_id uuid NOT NULL DEFAULT uuidv7(), name text NOT NULL, transport_code text NOT NULL,
    description text, created_at timestamptz NOT NULL DEFAULT now(), updated_at timestamptz NOT NULL DEFAULT now(),
    created_by_actor_id uuid NOT NULL, created_role_code text NOT NULL,
    CONSTRAINT pk_mcp_server PRIMARY KEY (mcp_server_id),
    CONSTRAINT fk_mcp_server_transport FOREIGN KEY (transport_code) REFERENCES reference.tool_transport (code),
    CONSTRAINT fk_mcp_server_created_by FOREIGN KEY (created_by_actor_id) REFERENCES core.actor (actor_id),
    CONSTRAINT fk_mcp_server_created_role FOREIGN KEY (created_role_code) REFERENCES reference.role (code),
    CONSTRAINT uq_mcp_server_name UNIQUE (name));
COMMENT ON TABLE core.mcp_server IS
'A reusable MCP server an agent may use (agent-only at assignment time). Versioned config lives in mcp_server_version; no lifecycle of its own (D5).

@tier 1
@lifecycle mutable
@subject registry
@status reference.tool_transport
@decision D5';
COMMENT ON COLUMN core.mcp_server.mcp_server_id IS
'Identity of the MCP server.';
COMMENT ON COLUMN core.mcp_server.name IS
'Human name; unique.';
COMMENT ON COLUMN core.mcp_server.transport_code IS
'How the server is reached. @status reference.tool_transport';
COMMENT ON COLUMN core.mcp_server.description IS
'What the server provides.';
COMMENT ON COLUMN core.mcp_server.created_at IS
'When created.';
COMMENT ON COLUMN core.mcp_server.updated_at IS
'When last updated.';
COMMENT ON COLUMN core.mcp_server.created_by_actor_id IS
'Who created it. @ref core.actor hard';
COMMENT ON COLUMN core.mcp_server.created_role_code IS
'The capacity they acted in. @status reference.role';
