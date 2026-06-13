-- Minimal registry primitive + intake↔asset linking + the promotion gate (003 US2). Reuses the
-- executable / executable_version / lifecycle_event / champion_assignment tables + entity_lifecycle_
-- current view. The gate is enforced in the service (registry.service.advance_lifecycle).

-- name: create_executable^
INSERT INTO core.executable (kind_code, name, display_name, description, application_id, created_by_actor_id, created_role_code)
VALUES (%(kind_code)s, %(name)s, %(display_name)s, %(description)s, %(application_id)s, %(created_by_actor_id)s, %(created_role_code)s)
RETURNING executable_id, kind_code, name, display_name, application_id;

-- name: get_executable^
SELECT executable_id, kind_code, name FROM core.executable WHERE executable_id = %(executable_id)s;

-- name: version_count^
SELECT count(*) AS n FROM core.executable_version WHERE executable_id = %(executable_id)s;

-- name: create_version^
INSERT INTO core.executable_version (executable_id, kind_code, semver, created_by_actor_id, created_role_code)
VALUES (%(executable_id)s, %(kind_code)s, %(semver)s, %(created_by_actor_id)s, %(created_role_code)s)
RETURNING executable_version_id, executable_id, semver;

-- name: get_version^
SELECT executable_version_id, executable_id, kind_code, semver FROM core.executable_version WHERE executable_version_id = %(version_id)s;

-- name: current_state^
SELECT lifecycle_state_code FROM core.entity_lifecycle_current WHERE executable_version_id = %(version_id)s;

-- name: insert_lifecycle_event^
INSERT INTO core.lifecycle_event (executable_version_id, from_state_code, to_state_code, approval_request_id, rationale, detail, actor_id, acting_role_code)
VALUES (%(version_id)s, %(from_state)s, %(to_state)s, %(approval_request_id)s, %(rationale)s, %(detail)s, %(actor_id)s, %(acting_role_code)s)
RETURNING lifecycle_event_id;

-- name: insert_champion!
INSERT INTO core.champion_assignment (executable_version_id, lifecycle_event_id, reason, actor_id, acting_role_code)
VALUES (%(version_id)s, %(lifecycle_event_id)s, %(reason)s, %(actor_id)s, %(acting_role_code)s);

-- name: list_executables
SELECT e.executable_id, e.kind_code, e.name, e.display_name,
       e.application_id, a.code AS application_code, a.name AS application_name,
       e.updated_at,
       (SELECT count(*) FROM core.executable_version v WHERE v.executable_id = e.executable_id) AS version_count
FROM core.executable e
LEFT JOIN core.application a ON a.application_id = e.application_id
ORDER BY e.created_at DESC;

-- name: list_executable_versions
SELECT v.executable_version_id, v.semver, lc.lifecycle_state_code, v.created_at
FROM core.executable_version v
LEFT JOIN core.entity_lifecycle_current lc ON lc.executable_version_id = v.executable_version_id
WHERE v.executable_id = %(executable_id)s ORDER BY v.created_at;

-- ── intake ↔ asset linking ────────────────────────────────────────────────────────────────────
-- name: insert_link^
INSERT INTO core.intake_entity_link (intake_id, intake_requirement_id, executable_id, created_by_actor_id, created_role_code)
VALUES (%(intake_id)s, %(intake_requirement_id)s, %(executable_id)s, %(created_by_actor_id)s, %(created_role_code)s)
RETURNING intake_entity_link_id;

-- name: link_for_executable^
-- The intake an asset is linked to (≤1 per asset) + that intake's status — used by the promotion gate.
SELECT l.intake_entity_link_id, l.intake_id, i.intake_status_code, i.title AS intake_title
FROM core.intake_entity_link l JOIN core.intake i ON i.intake_id = l.intake_id
WHERE l.executable_id = %(executable_id)s ORDER BY l.created_by_actor_id LIMIT 1;

-- name: get_executable_with_app^
-- Single executable with application name and code for the detail page.
SELECT e.executable_id, e.kind_code, e.name, e.display_name, e.description,
       e.application_id, a.code AS application_code, a.name AS application_name
FROM core.executable e
LEFT JOIN core.application a ON a.application_id = e.application_id
WHERE e.executable_id = %(executable_id)s;

-- name: delete_link!
DELETE FROM core.intake_entity_link WHERE intake_entity_link_id = %(link_id)s;

-- name: asset_top_stage^
-- The most-advanced lifecycle stage across an executable's versions (for the early-stage link gate +
-- the intake roll-up).
SELECT (SELECT lc.lifecycle_state_code FROM core.executable_version v
          JOIN core.entity_lifecycle_current lc ON lc.executable_version_id = v.executable_version_id
          WHERE v.executable_id = %(executable_id)s
          ORDER BY array_position(ARRAY['draft','candidate','staging','challenger','champion','deprecated'], lc.lifecycle_state_code) DESC NULLS LAST
          LIMIT 1) AS top_stage;

-- name: list_intake_links
SELECT l.intake_entity_link_id, l.executable_id, e.name, e.kind_code,
       (SELECT lc.lifecycle_state_code FROM core.executable_version v
          JOIN core.entity_lifecycle_current lc ON lc.executable_version_id = v.executable_version_id
          WHERE v.executable_id = e.executable_id
          ORDER BY array_position(ARRAY['draft','candidate','staging','challenger','champion','deprecated'], lc.lifecycle_state_code) DESC NULLS LAST
          LIMIT 1) AS top_stage
FROM core.intake_entity_link l JOIN core.executable e ON e.executable_id = l.executable_id
WHERE l.intake_id = %(intake_id)s ORDER BY e.name;

-- ── Feature 005 extensions ────────────────────────────────────────────────────

-- name: get_version_detail^
-- Full version row plus current lifecycle stage and champion flag.
SELECT v.executable_version_id, v.executable_id, v.kind_code, v.semver,
       v.governance_tier_code, v.capability_type_code, v.trust_level_code,
       v.data_classification_code, v.inference_config_id,
       v.input_schema, v.output_schema, v.cloned_from_version_id,
       lc.lifecycle_state_code AS lifecycle_stage
FROM core.executable_version v
LEFT JOIN core.entity_lifecycle_current lc ON lc.executable_version_id = v.executable_version_id
WHERE v.executable_version_id = %(version_id)s;

-- name: champion_current^
-- Current champion version for an executable via entity_champion_current view.
SELECT ecc.executable_version_id,
       v.semver, v.kind_code, v.governance_tier_code, v.capability_type_code,
       v.trust_level_code, v.data_classification_code, v.inference_config_id,
       v.input_schema, v.output_schema, v.cloned_from_version_id,
       lc.lifecycle_state_code AS lifecycle_stage
FROM core.entity_champion_current ecc
JOIN core.executable_version v ON v.executable_version_id = ecc.executable_version_id
LEFT JOIN core.entity_lifecycle_current lc ON lc.executable_version_id = ecc.executable_version_id
WHERE ecc.executable_id = %(executable_id)s;

-- name: champion_as_of^
-- Champion at a specific point in time (window query on champion_assignment).
SELECT ca.executable_version_id,
       v.semver, v.kind_code, v.governance_tier_code, v.capability_type_code,
       v.trust_level_code, v.data_classification_code, v.inference_config_id,
       v.input_schema, v.output_schema, v.cloned_from_version_id,
       lc.lifecycle_state_code AS lifecycle_stage
FROM (
    SELECT DISTINCT ON (ev.executable_id)
           ca.executable_version_id, ca.is_revocation
    FROM   core.champion_assignment ca
    JOIN   core.executable_version ev ON ev.executable_version_id = ca.executable_version_id
    WHERE  ev.executable_id = %(executable_id)s
      AND  ca.created_at <= %(as_of)s
    ORDER  BY ev.executable_id, ca.created_at DESC
) ca
JOIN core.executable_version v ON v.executable_version_id = ca.executable_version_id
LEFT JOIN core.entity_lifecycle_current lc ON lc.executable_version_id = ca.executable_version_id
WHERE NOT ca.is_revocation;

-- name: revoke_champion!
-- INSERT a revocation row for the current champion of the given executable.
-- No-op if the executable has no current champion.
-- clock_timestamp() ensures the revocation row gets an earlier wall-clock stamp
-- than the promotion row that follows in the same transaction (now() is frozen).
INSERT INTO core.champion_assignment
    (executable_version_id, is_revocation, reason, actor_id, acting_role_code, created_at)
SELECT ecc.executable_version_id, true, 'superseded', %(actor_id)s, %(acting_role_code)s, clock_timestamp()
FROM core.entity_champion_current ecc
WHERE ecc.executable_id = %(executable_id)s;

-- name: insert_champion_promotion!
-- INSERT a new champion assignment row for the promoted version.
-- clock_timestamp() advances within the transaction so this row sorts after the
-- revocation row that was inserted moments earlier by revoke_champion.
INSERT INTO core.champion_assignment
    (executable_version_id, is_revocation, lifecycle_event_id, reason, actor_id, acting_role_code, created_at)
VALUES (%(version_id)s, false, %(lifecycle_event_id)s, %(reason)s, %(actor_id)s, %(acting_role_code)s, clock_timestamp());

-- name: get_executable_detail^
-- Executable header with version list for ExecutableDetail.
SELECT e.executable_id, e.kind_code, e.name, e.display_name, e.description,
       e.application_id, a.code AS application_code, a.name AS application_name,
       (SELECT count(*) FROM core.executable_version v WHERE v.executable_id = e.executable_id) AS version_count,
       (SELECT v2.semver FROM core.entity_champion_current ecc
          JOIN core.executable_version v2 ON v2.executable_version_id = ecc.executable_version_id
          WHERE ecc.executable_id = e.executable_id) AS champion_semver
FROM core.executable e
LEFT JOIN core.application a ON a.application_id = e.application_id
WHERE e.executable_id = %(executable_id)s;

-- name: list_executables_filtered
-- List executables with optional kind_code filter; returns champion_semver, champion governance
-- fields, and application_id via subqueries.
SELECT e.executable_id, e.kind_code, e.name, e.display_name, e.description,
       e.application_id, a.code AS application_code, a.name AS application_name,
       e.updated_at,
       (SELECT count(*) FROM core.executable_version v WHERE v.executable_id = e.executable_id) AS version_count,
       (SELECT ecc.executable_version_id FROM core.entity_champion_current ecc
          WHERE ecc.executable_id = e.executable_id) AS champion_version_id,
       (SELECT v2.semver FROM core.entity_champion_current ecc
          JOIN core.executable_version v2 ON v2.executable_version_id = ecc.executable_version_id
          WHERE ecc.executable_id = e.executable_id) AS champion_semver,
       (SELECT v2.governance_tier_code FROM core.entity_champion_current ecc
          JOIN core.executable_version v2 ON v2.executable_version_id = ecc.executable_version_id
          WHERE ecc.executable_id = e.executable_id) AS champion_governance_tier_code,
       (SELECT v2.capability_type_code FROM core.entity_champion_current ecc
          JOIN core.executable_version v2 ON v2.executable_version_id = ecc.executable_version_id
          WHERE ecc.executable_id = e.executable_id) AS champion_capability_type_code
FROM core.executable e
LEFT JOIN core.application a ON a.application_id = e.application_id
WHERE (%(kind_code)s::text IS NULL OR e.kind_code = %(kind_code)s::text)
  AND (%(application_id)s::uuid IS NULL OR e.application_id = %(application_id)s::uuid)
ORDER BY e.created_at DESC;

-- name: create_version_full^
-- Create an executable version with full governance fields.
INSERT INTO core.executable_version
    (executable_id, kind_code, semver, governance_tier_code, capability_type_code,
     trust_level_code, data_classification_code, inference_config_id,
     input_schema, output_schema, version_change_type_code, cloned_from_version_id,
     created_by_actor_id, created_role_code)
VALUES
    (%(executable_id)s, %(kind_code)s, %(semver)s, %(governance_tier_code)s, %(capability_type_code)s,
     %(trust_level_code)s, %(data_classification_code)s, %(inference_config_id)s,
     %(input_schema)s, %(output_schema)s, %(version_change_type_code)s, %(cloned_from_version_id)s,
     %(created_by_actor_id)s, %(created_role_code)s)
RETURNING executable_version_id, executable_id, kind_code, semver,
          governance_tier_code, capability_type_code, trust_level_code,
          data_classification_code, inference_config_id, input_schema, output_schema,
          cloned_from_version_id;

-- ── Where-used reverse lookups ────────────────────────────────────────────────

-- name: where_used_prompt_version
SELECT e.executable_id, e.name AS executable_name, e.kind_code,
       a.executable_version_id, v.semver
FROM core.executable_prompt_assignment a
JOIN core.executable_version v ON v.executable_version_id = a.executable_version_id
JOIN core.executable e ON e.executable_id = v.executable_id
WHERE a.prompt_version_id = %(prompt_version_id)s
ORDER BY e.name, v.semver;

-- name: where_used_tool_version
SELECT e.executable_id, e.name AS executable_name, e.kind_code,
       a.executable_version_id, v.semver
FROM core.executable_tool_assignment a
JOIN core.executable_version v ON v.executable_version_id = a.executable_version_id
JOIN core.executable e ON e.executable_id = v.executable_id
WHERE a.tool_version_id = %(tool_version_id)s
ORDER BY e.name, v.semver;

-- name: where_used_mcp_version
SELECT e.executable_id, e.name AS executable_name, e.kind_code,
       a.executable_version_id, v.semver
FROM core.executable_mcp_assignment a
JOIN core.executable_version v ON v.executable_version_id = a.executable_version_id
JOIN core.executable e ON e.executable_id = v.executable_id
WHERE a.mcp_server_version_id = %(mcp_server_version_id)s
ORDER BY e.name, v.semver;

-- ── Sub-agent delegations ─────────────────────────────────────────────────────

-- name: list_delegations_for_parent
SELECT d.delegation_id, d.parent_version_id,
       d.child_executable_id, e.name AS child_name, e.kind_code AS child_kind,
       d.child_version_id,
       d.scope, d.rationale, d.notes, d.created_at
FROM core.executable_version_delegation d
LEFT JOIN core.executable e ON e.executable_id = d.child_executable_id
WHERE d.parent_version_id = %(parent_version_id)s
ORDER BY d.created_at;

-- name: insert_delegation^
INSERT INTO core.executable_version_delegation
    (parent_version_id, child_executable_id, child_version_id, scope, rationale, notes)
VALUES
    (%(parent_version_id)s, %(child_executable_id)s, %(child_version_id)s,
     %(scope)s, %(rationale)s, %(notes)s)
RETURNING delegation_id, created_at;

-- name: delete_delegation!
DELETE FROM core.executable_version_delegation
WHERE delegation_id = %(delegation_id)s AND parent_version_id = %(parent_version_id)s;

-- ── Model used-by ─────────────────────────────────────────────────────────────

-- name: list_executables_by_model
-- Which champion agent/task versions resolve to this model via their inference config chain.
SELECT DISTINCT e.executable_id, e.name AS executable_name, e.kind_code,
       v.executable_version_id, v.semver
FROM core.entity_champion_current ecc
JOIN core.executable_version v ON v.executable_version_id = ecc.executable_version_id
JOIN core.executable e ON e.executable_id = ecc.executable_id
JOIN core.inference_config_model icm ON icm.inference_config_id = v.inference_config_id
JOIN core.model_reference_binding mrb ON mrb.model_reference_id = icm.model_reference_id
    AND mrb.valid_to = '2099-12-31 00:00:00+00'
WHERE mrb.model_id = %(model_id)s
ORDER BY e.name;
