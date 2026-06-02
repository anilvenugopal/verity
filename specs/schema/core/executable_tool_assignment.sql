-- core.executable_tool_assignment  ·  subject: registry  ·  (table)

-- Tools: AGENT-ONLY. Enforced at the DB by pinning kind via composite FK + CHECK.
CREATE TABLE core.executable_tool_assignment (
    executable_version_id uuid NOT NULL, tool_version_id uuid NOT NULL,
    executable_kind_code text NOT NULL,                       -- must be 'agent'
    CONSTRAINT pk_executable_tool_assignment PRIMARY KEY (executable_version_id, tool_version_id),
    CONSTRAINT fk_eta_executable_version FOREIGN KEY (executable_version_id, executable_kind_code)
        REFERENCES core.executable_version (executable_version_id, kind_code) ON DELETE CASCADE,
    CONSTRAINT fk_eta_tool_version FOREIGN KEY (tool_version_id) REFERENCES core.tool_version (tool_version_id) ON DELETE RESTRICT,
    CONSTRAINT ck_eta_agent_only CHECK (executable_kind_code = 'agent'));
COMMENT ON TABLE core.executable_tool_assignment IS 'tier:1. Tool attached to an AGENT version. agent-only enforced by composite FK to (executable_version_id, kind_code) + CHECK kind=agent (binding-grammar). D5.';
