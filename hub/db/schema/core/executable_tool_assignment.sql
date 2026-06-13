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
COMMENT ON TABLE core.executable_tool_assignment IS
'Attaches a tool_version to an AGENT version. agent-only is enforced at the database by a composite FK to (executable_version_id, kind_code) plus a CHECK that the kind is agent — so a task can never be given a tool (D5, binding-grammar).

@tier 1
@lifecycle mutable
@subject registry
@invariant agent-only, enforced by composite FK + CHECK
@decision D5';
COMMENT ON COLUMN core.executable_tool_assignment.executable_version_id IS
'The agent version using the tool. @ref core.executable_version hard';
COMMENT ON COLUMN core.executable_tool_assignment.tool_version_id IS
'The exact tool version pinned. @ref core.tool_version hard';
COMMENT ON COLUMN core.executable_tool_assignment.executable_kind_code IS
'Must be agent; the composite FK + CHECK is what enforces agent-only.';
