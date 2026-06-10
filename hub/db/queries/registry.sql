-- Minimal registry primitive + intake↔asset linking + the promotion gate (003 US2). Reuses the
-- executable / executable_version / lifecycle_event / champion_assignment tables + entity_lifecycle_
-- current view. The gate is enforced in the service (registry.service.advance_lifecycle).

-- name: create_executable^
INSERT INTO core.executable (kind_code, name, description, created_by_actor_id, created_role_code)
VALUES (%(kind_code)s, %(name)s, %(description)s, %(created_by_actor_id)s, %(created_role_code)s)
RETURNING executable_id, kind_code, name;

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
SELECT e.executable_id, e.kind_code, e.name,
       (SELECT count(*) FROM core.executable_version v WHERE v.executable_id = e.executable_id) AS version_count
FROM core.executable e ORDER BY e.created_at DESC;

-- name: list_executable_versions
SELECT v.executable_version_id, v.semver, lc.lifecycle_state_code
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
SELECT l.intake_entity_link_id, l.intake_id, i.intake_status_code
FROM core.intake_entity_link l JOIN core.intake i ON i.intake_id = l.intake_id
WHERE l.executable_id = %(executable_id)s ORDER BY l.created_by_actor_id LIMIT 1;

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
