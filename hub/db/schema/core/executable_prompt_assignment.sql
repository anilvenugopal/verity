-- core.executable_prompt_assignment  ·  subject: registry  ·  (table)

-- Prompts: uniform for agent AND task (binding-grammar). Junction = composite NK (D2).
CREATE TABLE core.executable_prompt_assignment (
    executable_version_id uuid NOT NULL, prompt_version_id uuid NOT NULL, api_role_code text NOT NULL,
    ordinal integer NOT NULL DEFAULT 1,
    CONSTRAINT pk_executable_prompt_assignment PRIMARY KEY (executable_version_id, prompt_version_id, api_role_code),
    CONSTRAINT fk_epa_executable_version FOREIGN KEY (executable_version_id) REFERENCES core.executable_version (executable_version_id) ON DELETE CASCADE,
    CONSTRAINT fk_epa_prompt_version FOREIGN KEY (prompt_version_id) REFERENCES core.prompt_version (prompt_version_id) ON DELETE RESTRICT,
    CONSTRAINT fk_epa_api_role FOREIGN KEY (api_role_code) REFERENCES reference.api_role (code));
COMMENT ON TABLE core.executable_prompt_assignment IS
'Attaches a prompt_version to an executable_version in a given API role (system/user/...). Uniform for agents and tasks; the composite key is the assignment identity (D5, binding-grammar).

@tier 1
@lifecycle mutable
@subject registry
@status reference.api_role
@decision D5';
COMMENT ON COLUMN core.executable_prompt_assignment.executable_version_id IS
'The version using the prompt. @ref core.executable_version hard';
COMMENT ON COLUMN core.executable_prompt_assignment.prompt_version_id IS
'The exact prompt version pinned. @ref core.prompt_version hard';
COMMENT ON COLUMN core.executable_prompt_assignment.api_role_code IS
'The chat role the prompt fills (system/user/...). @status reference.api_role';
COMMENT ON COLUMN core.executable_prompt_assignment.ordinal IS
'Order among prompts sharing a role.';
