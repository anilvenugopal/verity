-- registry_bindings.sql — feature 005 (US4).
-- Source and target data bindings for executable versions.

-- ── Source Bindings ───────────────────────────────────────────────────────────

-- name: create_source_binding^
INSERT INTO core.source_binding
    (executable_version_id, name, source_kind_code, data_connector_version_id,
     delivery_mode_code, media_type, locator, nullable, ordinal)
VALUES
    (%(executable_version_id)s, %(name)s, %(source_kind_code)s, %(data_connector_version_id)s,
     %(delivery_mode_code)s, %(media_type)s, %(locator)s, %(nullable)s, %(ordinal)s)
RETURNING source_binding_id, executable_version_id, name, source_kind_code,
          data_connector_version_id, delivery_mode_code, media_type, locator, nullable, ordinal;

-- name: list_source_bindings
SELECT source_binding_id, executable_version_id, name, source_kind_code,
       data_connector_version_id, delivery_mode_code, media_type, locator, nullable, ordinal
FROM core.source_binding
WHERE executable_version_id = %(executable_version_id)s
ORDER BY ordinal, name;

-- name: delete_source_binding!
DELETE FROM core.source_binding
WHERE source_binding_id = %(source_binding_id)s
  AND executable_version_id = %(executable_version_id)s;

-- ── Target Bindings ───────────────────────────────────────────────────────────

-- name: create_target_binding^
INSERT INTO core.target_binding
    (executable_version_id, name, target_kind_code, data_connector_version_id,
     delivery_mode_code, write_mode_code, target_payload_field, locator, ordinal)
VALUES
    (%(executable_version_id)s, %(name)s, %(target_kind_code)s, %(data_connector_version_id)s,
     %(delivery_mode_code)s, %(write_mode_code)s, %(target_payload_field)s, %(locator)s, %(ordinal)s)
RETURNING target_binding_id, executable_version_id, name, target_kind_code,
          data_connector_version_id, delivery_mode_code, write_mode_code,
          target_payload_field, locator, ordinal;

-- name: list_target_bindings
SELECT target_binding_id, executable_version_id, name, target_kind_code,
       data_connector_version_id, delivery_mode_code, write_mode_code,
       target_payload_field, locator, ordinal
FROM core.target_binding
WHERE executable_version_id = %(executable_version_id)s
ORDER BY ordinal, name;

-- name: delete_target_binding!
DELETE FROM core.target_binding
WHERE target_binding_id = %(target_binding_id)s
  AND executable_version_id = %(executable_version_id)s;
