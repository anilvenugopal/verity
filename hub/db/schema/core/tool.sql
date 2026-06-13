-- core.tool  ·  subject: registry  ·  (table)

-- tool (agent-only at assignment time)
CREATE TABLE core.tool (
    tool_id uuid NOT NULL DEFAULT uuidv7(), name text NOT NULL, display_name text, description text,
    transport_code text NOT NULL,
    is_write_operation boolean NOT NULL DEFAULT false,
    application_id uuid,
    created_at timestamptz NOT NULL DEFAULT now(), updated_at timestamptz NOT NULL DEFAULT now(),
    created_by_actor_id uuid NOT NULL, created_role_code text NOT NULL,
    CONSTRAINT pk_tool PRIMARY KEY (tool_id),
    CONSTRAINT fk_tool_transport FOREIGN KEY (transport_code) REFERENCES reference.tool_transport (code),
    CONSTRAINT fk_tool_created_by FOREIGN KEY (created_by_actor_id) REFERENCES core.actor (actor_id),
    CONSTRAINT fk_tool_created_role FOREIGN KEY (created_role_code) REFERENCES reference.role (code),
    CONSTRAINT uq_tool_name UNIQUE (name));
CREATE UNIQUE INDEX uq_tool_app_display ON core.tool (application_id, display_name) WHERE application_id IS NOT NULL;
COMMENT ON TABLE core.tool IS
'A reusable tool component an agent may call (agent-only at assignment time). Versioned config lives in tool_version; the tool itself has no lifecycle (D5).

@tier 1
@lifecycle mutable
@subject registry
@status reference.tool_transport
@decision D5';
COMMENT ON COLUMN core.tool.tool_id IS
'Identity of the tool.';
COMMENT ON COLUMN core.tool.name IS
'Technical name; unique.';
COMMENT ON COLUMN core.tool.display_name IS
'Human-readable label shown in the UI.';
COMMENT ON COLUMN core.tool.is_write_operation IS
'True when this tool mutates external state; governs trust/audit requirements.';
COMMENT ON COLUMN core.tool.description IS
'What the tool does.';
COMMENT ON COLUMN core.tool.transport_code IS
'How the tool is invoked. @status reference.tool_transport';
COMMENT ON COLUMN core.tool.created_at IS
'When created.';
COMMENT ON COLUMN core.tool.updated_at IS
'When last updated.';
COMMENT ON COLUMN core.tool.created_by_actor_id IS
'Who created it. @ref core.actor hard';
COMMENT ON COLUMN core.tool.created_role_code IS
'The capacity they acted in. @status reference.role';
