-- core.prompt  ·  subject: registry  ·  (table)

-- prompt
CREATE TABLE core.prompt (
    prompt_id uuid NOT NULL DEFAULT uuidv7(), name text NOT NULL, description text,
    created_at timestamptz NOT NULL DEFAULT now(), updated_at timestamptz NOT NULL DEFAULT now(),
    created_by_actor_id uuid NOT NULL, created_role_code text NOT NULL,
    CONSTRAINT pk_prompt PRIMARY KEY (prompt_id),
    CONSTRAINT fk_prompt_created_by FOREIGN KEY (created_by_actor_id) REFERENCES core.actor (actor_id),
    CONSTRAINT fk_prompt_created_role FOREIGN KEY (created_role_code) REFERENCES reference.role (code),
    CONSTRAINT uq_prompt_name UNIQUE (name));
COMMENT ON TABLE core.prompt IS 'tier:1 component (no lifecycle). Reusable prompt; content lives in prompt_version. D5.';
