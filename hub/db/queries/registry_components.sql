-- registry_components.sql — feature 005 (US1, US2).
-- Prompts, tools, MCP servers, data connectors, inference configs, and their
-- composition assignments. All queries follow the aiosql apsycopg conventions used
-- throughout the codebase (%(param)s placeholders, ^ = one-row, ! = write-only).

-- ── Prompts ───────────────────────────────────────────────────────────────────

-- name: create_prompt^
INSERT INTO core.prompt (name, display_name, description, application_id, created_by_actor_id, created_role_code)
VALUES (%(name)s, %(display_name)s, %(description)s, %(application_id)s, %(created_by_actor_id)s, %(created_role_code)s)
RETURNING prompt_id, name, display_name, description, application_id;

-- name: get_prompt^
SELECT p.prompt_id, p.name, p.display_name, p.description,
       p.application_id, a.code AS application_code, a.name AS application_name
FROM core.prompt p
LEFT JOIN core.application a ON a.application_id = p.application_id
WHERE p.prompt_id = %(prompt_id)s;

-- name: list_prompts
SELECT p.prompt_id, p.name, p.display_name, p.description,
       p.application_id, a.code AS application_code, a.name AS application_name,
       (SELECT count(*) FROM core.prompt_version v WHERE v.prompt_id = p.prompt_id) AS version_count,
       (SELECT pv.prompt_version_id FROM core.prompt_version pv
          WHERE pv.prompt_id = p.prompt_id ORDER BY pv.created_at DESC LIMIT 1) AS latest_version_id
FROM core.prompt p
LEFT JOIN core.application a ON a.application_id = p.application_id
WHERE (%(application_id)s::uuid IS NULL OR p.application_id = %(application_id)s::uuid)
ORDER BY p.display_name;

-- name: create_prompt_version^
INSERT INTO core.prompt_version (prompt_id, semver, blocks, content_hash, created_by_actor_id, created_role_code)
VALUES (%(prompt_id)s, %(semver)s, %(blocks)s, %(content_hash)s, %(created_by_actor_id)s, %(created_role_code)s)
RETURNING prompt_version_id, prompt_id, semver, content_hash;

-- name: get_prompt_version^
SELECT prompt_version_id, prompt_id, semver, content_hash, blocks
FROM core.prompt_version WHERE prompt_version_id = %(prompt_version_id)s;

-- name: list_prompt_versions
SELECT prompt_version_id, prompt_id, semver, content_hash
FROM core.prompt_version WHERE prompt_id = %(prompt_id)s ORDER BY created_at;

-- ── Tools ─────────────────────────────────────────────────────────────────────

-- name: create_tool^
INSERT INTO core.tool (name, display_name, description, transport_code, application_id, created_by_actor_id, created_role_code)
VALUES (%(name)s, %(display_name)s, %(description)s, %(transport_code)s, %(application_id)s, %(created_by_actor_id)s, %(created_role_code)s)
RETURNING tool_id, name, display_name, transport_code, description, application_id;

-- name: get_tool^
SELECT t.tool_id, t.name, t.display_name, t.transport_code, t.description, t.is_write_operation,
       t.application_id, a.code AS application_code, a.name AS application_name
FROM core.tool t
LEFT JOIN core.application a ON a.application_id = t.application_id
WHERE t.tool_id = %(tool_id)s;

-- name: list_tools
SELECT t.tool_id, t.name, t.display_name, t.transport_code, t.description, t.is_write_operation,
       t.application_id, a.code AS application_code, a.name AS application_name,
       (SELECT tv.tool_version_id FROM core.tool_version tv
          WHERE tv.tool_id = t.tool_id ORDER BY tv.created_at DESC LIMIT 1) AS latest_version_id
FROM core.tool t
LEFT JOIN core.application a ON a.application_id = t.application_id
WHERE (%(application_id)s::uuid IS NULL OR t.application_id = %(application_id)s::uuid)
ORDER BY t.display_name;

-- name: create_tool_version^
INSERT INTO core.tool_version (tool_id, semver, input_schema, config, data_classification_code, created_by_actor_id, created_role_code)
VALUES (%(tool_id)s, %(semver)s, %(input_schema)s, %(config)s, %(data_classification_code)s, %(created_by_actor_id)s, %(created_role_code)s)
RETURNING tool_version_id, tool_id, semver, data_classification_code;

-- name: list_tool_versions
SELECT tool_version_id, tool_id, semver, data_classification_code
FROM core.tool_version WHERE tool_id = %(tool_id)s ORDER BY created_at;

-- name: get_tool_version_detail^
SELECT tv.tool_version_id, tv.tool_id, t.name AS tool_name, t.transport_code, t.description,
       tv.semver, tv.input_schema, tv.data_classification_code
FROM core.tool_version tv
JOIN core.tool t ON t.tool_id = tv.tool_id
WHERE tv.tool_version_id = %(tool_version_id)s;

-- ── MCP Servers ───────────────────────────────────────────────────────────────

-- name: get_mcp_server_by_name^
SELECT mcp_server_id, name FROM core.mcp_server WHERE name = %(name)s;

-- name: create_mcp_server^
INSERT INTO core.mcp_server (name, transport_code, created_by_actor_id, created_role_code)
VALUES (%(name)s, %(transport_code)s, %(created_by_actor_id)s, %(created_role_code)s)
RETURNING mcp_server_id, name;

-- name: create_mcp_server_version^
INSERT INTO core.mcp_server_version (mcp_server_id, semver, config, created_by_actor_id, created_role_code)
VALUES (%(mcp_server_id)s, %(semver)s, %(config)s, %(created_by_actor_id)s, %(created_role_code)s)
RETURNING mcp_server_version_id, mcp_server_id, semver;

-- name: list_mcp_servers
SELECT v.mcp_server_version_id, s.name, v.semver
FROM core.mcp_server_version v
JOIN core.mcp_server s ON s.mcp_server_id = v.mcp_server_id
ORDER BY s.name, v.created_at;

-- ── Data Connectors ───────────────────────────────────────────────────────────

-- name: create_connector^
INSERT INTO core.data_connector (name, connector_type_code, description, created_by_actor_id, created_role_code)
VALUES (%(name)s, %(connector_type_code)s, %(description)s, %(created_by_actor_id)s, %(created_role_code)s)
RETURNING data_connector_id, name, connector_type_code;

-- name: get_connector^
SELECT data_connector_id, name, connector_type_code FROM core.data_connector WHERE data_connector_id = %(data_connector_id)s;

-- name: list_connectors
SELECT data_connector_id, name, connector_type_code FROM core.data_connector ORDER BY name;

-- name: create_connector_version^
INSERT INTO core.data_connector_version (data_connector_id, semver, config, created_by_actor_id, created_role_code)
VALUES (%(data_connector_id)s, %(semver)s, %(config)s, %(created_by_actor_id)s, %(created_role_code)s)
RETURNING data_connector_version_id, data_connector_id, semver;

-- name: list_connector_versions
SELECT data_connector_version_id, data_connector_id, semver
FROM core.data_connector_version WHERE data_connector_id = %(data_connector_id)s ORDER BY created_at;

-- ── Inference Configs ─────────────────────────────────────────────────────────

-- name: create_inference_config^
INSERT INTO core.inference_config (max_tokens, temperature, params)
VALUES (%(max_tokens)s, %(temperature)s, %(params)s)
RETURNING inference_config_id, max_tokens, temperature, params;

-- name: get_inference_config^
SELECT inference_config_id, max_tokens, temperature, params
FROM core.inference_config WHERE inference_config_id = %(inference_config_id)s;

-- name: add_inference_config_model!
INSERT INTO core.inference_config_model (inference_config_id, model_reference_id, priority)
VALUES (%(inference_config_id)s, %(model_reference_id)s, %(priority)s);

-- name: list_inference_config_models
SELECT inference_config_id, model_reference_id, priority
FROM core.inference_config_model WHERE inference_config_id = %(inference_config_id)s ORDER BY priority;

-- ── Composition: Prompt Assignments ──────────────────────────────────────────

-- name: add_prompt_assignment^
INSERT INTO core.executable_prompt_assignment (executable_version_id, prompt_version_id, api_role_code, ordinal)
VALUES (%(executable_version_id)s, %(prompt_version_id)s, %(api_role_code)s, %(ordinal)s)
ON CONFLICT DO NOTHING
RETURNING executable_version_id, prompt_version_id, api_role_code, ordinal;

-- name: list_prompt_assignments
SELECT a.executable_version_id, a.prompt_version_id, p.name AS prompt_name,
       pv.semver AS prompt_semver, a.api_role_code, a.ordinal
FROM core.executable_prompt_assignment a
JOIN core.prompt_version pv ON pv.prompt_version_id = a.prompt_version_id
JOIN core.prompt p ON p.prompt_id = pv.prompt_id
WHERE a.executable_version_id = %(executable_version_id)s
ORDER BY a.api_role_code, a.ordinal;

-- name: remove_prompt_assignment!
DELETE FROM core.executable_prompt_assignment
WHERE executable_version_id = %(executable_version_id)s
  AND prompt_version_id = %(prompt_version_id)s
  AND api_role_code = %(api_role_code)s;

-- name: count_prompt_assignments^
SELECT count(*) AS n
FROM core.executable_prompt_assignment
WHERE executable_version_id = %(executable_version_id)s;

-- ── Composition: Tool Assignments ─────────────────────────────────────────────

-- name: add_tool_assignment^
INSERT INTO core.executable_tool_assignment (executable_version_id, tool_version_id, executable_kind_code)
VALUES (%(executable_version_id)s, %(tool_version_id)s, %(executable_kind_code)s)
ON CONFLICT DO NOTHING
RETURNING executable_version_id, tool_version_id;

-- name: list_tool_assignments
SELECT a.executable_version_id, a.tool_version_id, t.name AS tool_name, tv.semver AS tool_semver
FROM core.executable_tool_assignment a
JOIN core.tool_version tv ON tv.tool_version_id = a.tool_version_id
JOIN core.tool t ON t.tool_id = tv.tool_id
WHERE a.executable_version_id = %(executable_version_id)s
ORDER BY t.name;

-- name: remove_tool_assignment!
DELETE FROM core.executable_tool_assignment
WHERE executable_version_id = %(executable_version_id)s
  AND tool_version_id = %(tool_version_id)s;

-- ── Composition: MCP Assignments ──────────────────────────────────────────────

-- name: add_mcp_assignment^
INSERT INTO core.executable_mcp_assignment (executable_version_id, mcp_server_version_id, executable_kind_code)
VALUES (%(executable_version_id)s, %(mcp_server_version_id)s, %(executable_kind_code)s)
ON CONFLICT DO NOTHING
RETURNING executable_version_id, mcp_server_version_id;

-- name: list_mcp_assignments
SELECT a.executable_version_id, a.mcp_server_version_id, s.name, v.semver
FROM core.executable_mcp_assignment a
JOIN core.mcp_server_version v ON v.mcp_server_version_id = a.mcp_server_version_id
JOIN core.mcp_server s ON s.mcp_server_id = v.mcp_server_id
WHERE a.executable_version_id = %(executable_version_id)s
ORDER BY s.name;

-- name: remove_mcp_assignment!
DELETE FROM core.executable_mcp_assignment
WHERE executable_version_id = %(executable_version_id)s
  AND mcp_server_version_id = %(mcp_server_version_id)s;
