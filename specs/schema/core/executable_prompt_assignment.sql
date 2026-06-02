-- core.executable_prompt_assignment  ·  subject: registry  ·  (table)

-- Prompts: uniform for agent AND task (binding-grammar). Junction = composite NK (D2).
CREATE TABLE core.executable_prompt_assignment (
    executable_version_id uuid NOT NULL, prompt_version_id uuid NOT NULL, api_role_code text NOT NULL,
    ordinal integer NOT NULL DEFAULT 1,
    CONSTRAINT pk_executable_prompt_assignment PRIMARY KEY (executable_version_id, prompt_version_id, api_role_code),
    CONSTRAINT fk_epa_executable_version FOREIGN KEY (executable_version_id) REFERENCES core.executable_version (executable_version_id) ON DELETE CASCADE,
    CONSTRAINT fk_epa_prompt_version FOREIGN KEY (prompt_version_id) REFERENCES core.prompt_version (prompt_version_id) ON DELETE RESTRICT,
    CONSTRAINT fk_epa_api_role FOREIGN KEY (api_role_code) REFERENCES reference.api_role (code));
COMMENT ON TABLE core.executable_prompt_assignment IS 'tier:1. A prompt_version used by an executable_version in an api_role. Uniform for agent+task. D5.';
