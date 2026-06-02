-- core.tool_version  ·  subject: registry  ·  (table)

CREATE TABLE core.tool_version (
    tool_version_id uuid NOT NULL DEFAULT uuidv7(), tool_id uuid NOT NULL, semver text NOT NULL,
    input_schema jsonb, config jsonb NOT NULL DEFAULT '{}'::jsonb,
    valid_from timestamptz, valid_to timestamptz, created_at timestamptz NOT NULL DEFAULT now(),
    created_by_actor_id uuid NOT NULL, created_role_code text NOT NULL,
    CONSTRAINT pk_tool_version PRIMARY KEY (tool_version_id),
    CONSTRAINT fk_tool_version_tool FOREIGN KEY (tool_id) REFERENCES core.tool (tool_id) ON DELETE RESTRICT,
    CONSTRAINT fk_tool_version_created_by FOREIGN KEY (created_by_actor_id) REFERENCES core.actor (actor_id),
    CONSTRAINT fk_tool_version_created_role FOREIGN KEY (created_role_code) REFERENCES reference.role (code),
    CONSTRAINT uq_tool_version_semver UNIQUE (tool_id, semver));
