-- core.prompt  ·  subject: registry  ·  (table)

-- prompt
CREATE TABLE core.prompt (
    prompt_id uuid NOT NULL DEFAULT uuidv7(), name text NOT NULL, display_name text, description text,
    application_id uuid,
    created_at timestamptz NOT NULL DEFAULT now(), updated_at timestamptz NOT NULL DEFAULT now(),
    created_by_actor_id uuid NOT NULL, created_role_code text NOT NULL,
    CONSTRAINT pk_prompt PRIMARY KEY (prompt_id),
    CONSTRAINT fk_prompt_created_by FOREIGN KEY (created_by_actor_id) REFERENCES core.actor (actor_id),
    CONSTRAINT fk_prompt_created_role FOREIGN KEY (created_role_code) REFERENCES reference.role (code),
    CONSTRAINT uq_prompt_name UNIQUE (name));
CREATE UNIQUE INDEX uq_prompt_app_display ON core.prompt (application_id, display_name) WHERE application_id IS NOT NULL;
COMMENT ON TABLE core.prompt IS
'A reusable prompt component. It has no lifecycle or champion of its own — it is governed within whatever executable version uses it; the editable content lives in prompt_version (D5).

@tier 1
@lifecycle mutable
@subject registry
@decision D5';
COMMENT ON COLUMN core.prompt.prompt_id IS
'Identity of the prompt.';
COMMENT ON COLUMN core.prompt.name IS
'Technical name; unique.';
COMMENT ON COLUMN core.prompt.display_name IS
'Human-readable label shown in the UI.';
COMMENT ON COLUMN core.prompt.application_id IS
'Owning application. @ref core.application hard';
COMMENT ON COLUMN core.prompt.description IS
'What the prompt is for.';
COMMENT ON COLUMN core.prompt.created_at IS
'When created.';
COMMENT ON COLUMN core.prompt.updated_at IS
'When last updated.';
COMMENT ON COLUMN core.prompt.created_by_actor_id IS
'Who created it. @ref core.actor hard';
COMMENT ON COLUMN core.prompt.created_role_code IS
'The capacity they acted in. @status reference.role';
