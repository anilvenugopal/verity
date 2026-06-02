-- core.tool  ·  subject: registry  ·  (table)

-- tool (agent-only at assignment time)
CREATE TABLE core.tool (
    tool_id uuid NOT NULL DEFAULT uuidv7(), name text NOT NULL, description text,
    transport_code text NOT NULL,
    created_at timestamptz NOT NULL DEFAULT now(), updated_at timestamptz NOT NULL DEFAULT now(),
    created_by_actor_id uuid NOT NULL, created_role_code text NOT NULL,
    CONSTRAINT pk_tool PRIMARY KEY (tool_id),
    CONSTRAINT fk_tool_transport FOREIGN KEY (transport_code) REFERENCES reference.tool_transport (code),
    CONSTRAINT fk_tool_created_by FOREIGN KEY (created_by_actor_id) REFERENCES core.actor (actor_id),
    CONSTRAINT fk_tool_created_role FOREIGN KEY (created_role_code) REFERENCES reference.role (code),
    CONSTRAINT uq_tool_name UNIQUE (name));
