-- core.tool_version  ·  subject: registry  ·  (table)

CREATE TABLE core.tool_version (
    tool_version_id uuid NOT NULL DEFAULT uuidv7(), tool_id uuid NOT NULL, semver text NOT NULL,
    input_schema jsonb, config jsonb NOT NULL DEFAULT '{}'::jsonb,
    data_classification_code text,
    valid_from timestamptz NOT NULL DEFAULT now(), valid_to timestamptz NOT NULL DEFAULT '2099-12-31 00:00:00+00', created_at timestamptz NOT NULL DEFAULT now(),
    created_by_actor_id uuid NOT NULL, created_role_code text NOT NULL,
    CONSTRAINT pk_tool_version PRIMARY KEY (tool_version_id),
    CONSTRAINT fk_tool_version_tool FOREIGN KEY (tool_id) REFERENCES core.tool (tool_id) ON DELETE RESTRICT,
    CONSTRAINT fk_tool_version_created_by FOREIGN KEY (created_by_actor_id) REFERENCES core.actor (actor_id),
    CONSTRAINT fk_tool_version_created_role FOREIGN KEY (created_role_code) REFERENCES reference.role (code),
    CONSTRAINT fk_tool_version_data_class FOREIGN KEY (data_classification_code) REFERENCES reference.data_classification (code) ON DELETE RESTRICT,
    CONSTRAINT uq_tool_version_semver UNIQUE (tool_id, semver));
COMMENT ON TABLE core.tool_version IS
'An immutable version of a tool: its input schema and config, pinned so a run reproduces exactly what the tool looked like (D5).

@tier 1
@lifecycle scd2
@subject registry
@decision D5';
COMMENT ON COLUMN core.tool_version.tool_version_id IS
'Identity of the tool version.';
COMMENT ON COLUMN core.tool_version.tool_id IS
'The tool this versions. @ref core.tool hard';
COMMENT ON COLUMN core.tool_version.semver IS
'Semantic version within the tool; unique per tool.';
COMMENT ON COLUMN core.tool_version.input_schema IS
'Schema of the tools input arguments.';
COMMENT ON COLUMN core.tool_version.config IS
'Tool configuration for this version.';
COMMENT ON COLUMN core.tool_version.valid_from IS
'Start of the SCD-2 validity window.';
COMMENT ON COLUMN core.tool_version.valid_to IS
'End of the window; the open row (2099-12-31) is current.';
COMMENT ON COLUMN core.tool_version.created_at IS
'When created.';
COMMENT ON COLUMN core.tool_version.created_by_actor_id IS
'Who created it. @ref core.actor hard';
COMMENT ON COLUMN core.tool_version.data_classification_code IS
'Sensitivity level of data this tool version processes. @status reference.data_classification';
COMMENT ON COLUMN core.tool_version.created_role_code IS
'The capacity they acted in. @status reference.role';
