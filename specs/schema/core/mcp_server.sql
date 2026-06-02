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
