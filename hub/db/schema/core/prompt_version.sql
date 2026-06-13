-- core.prompt_version  ·  subject: registry  ·  (table)

CREATE TABLE core.prompt_version (
    prompt_version_id uuid NOT NULL DEFAULT uuidv7(), prompt_id uuid NOT NULL,
    semver text NOT NULL, blocks jsonb NOT NULL,            -- ordered typed blocks (prompt-editor)
    content_hash text NOT NULL,                              -- for blame/diff + reproduction
    valid_from timestamptz NOT NULL DEFAULT now(), valid_to timestamptz NOT NULL DEFAULT '2099-12-31 00:00:00+00',
    created_at timestamptz NOT NULL DEFAULT now(), created_by_actor_id uuid NOT NULL, created_role_code text NOT NULL,
    CONSTRAINT pk_prompt_version PRIMARY KEY (prompt_version_id),
    CONSTRAINT fk_prompt_version_prompt FOREIGN KEY (prompt_id) REFERENCES core.prompt (prompt_id) ON DELETE RESTRICT,
    CONSTRAINT fk_prompt_version_created_by FOREIGN KEY (created_by_actor_id) REFERENCES core.actor (actor_id),
    CONSTRAINT fk_prompt_version_created_role FOREIGN KEY (created_role_code) REFERENCES reference.role (code),
    CONSTRAINT uq_prompt_version_semver UNIQUE (prompt_id, semver));
COMMENT ON TABLE core.prompt_version IS
'An immutable version of a prompt: ordered typed blocks plus a content hash for blame/diff and exact historic reproduction. No lifecycle of its own — reproducibility comes from pinning a specific version inside an executable version (D5).

@tier 1
@lifecycle scd2
@subject registry
@decision D5';
COMMENT ON COLUMN core.prompt_version.prompt_version_id IS
'Identity of the prompt version.';
COMMENT ON COLUMN core.prompt_version.prompt_id IS
'The prompt this versions. @ref core.prompt hard';
COMMENT ON COLUMN core.prompt_version.semver IS
'Semantic version within the prompt; unique per prompt.';
COMMENT ON COLUMN core.prompt_version.blocks IS
'Ordered, typed prompt blocks authored in the prompt editor.';
COMMENT ON COLUMN core.prompt_version.content_hash IS
'Hash of the rendered content for blame/diff and reproduction.';
COMMENT ON COLUMN core.prompt_version.valid_from IS
'Start of the SCD-2 validity window.';
COMMENT ON COLUMN core.prompt_version.valid_to IS
'End of the window; the open row (2099-12-31) is current.';
COMMENT ON COLUMN core.prompt_version.created_at IS
'When created.';
COMMENT ON COLUMN core.prompt_version.created_by_actor_id IS
'Who created it. @ref core.actor hard';
COMMENT ON COLUMN core.prompt_version.created_role_code IS
'The capacity they acted in. @status reference.role';
