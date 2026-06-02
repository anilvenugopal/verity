-- core.prompt_version  ·  subject: registry  ·  (table)

CREATE TABLE core.prompt_version (
    prompt_version_id uuid NOT NULL DEFAULT uuidv7(), prompt_id uuid NOT NULL,
    semver text NOT NULL, blocks jsonb NOT NULL,            -- ordered typed blocks (prompt-editor)
    content_hash text NOT NULL,                              -- for blame/diff + reproduction
    valid_from timestamptz, valid_to timestamptz,
    created_at timestamptz NOT NULL DEFAULT now(), created_by_actor_id uuid NOT NULL, created_role_code text NOT NULL,
    CONSTRAINT pk_prompt_version PRIMARY KEY (prompt_version_id),
    CONSTRAINT fk_prompt_version_prompt FOREIGN KEY (prompt_id) REFERENCES core.prompt (prompt_id) ON DELETE RESTRICT,
    CONSTRAINT fk_prompt_version_created_by FOREIGN KEY (created_by_actor_id) REFERENCES core.actor (actor_id),
    CONSTRAINT fk_prompt_version_created_role FOREIGN KEY (created_role_code) REFERENCES reference.role (code),
    CONSTRAINT uq_prompt_version_semver UNIQUE (prompt_id, semver));
COMMENT ON TABLE core.prompt_version IS 'tier:1 immutable prompt version (full historic reproduction). No lifecycle — governed within the executable that uses it. D5.';
