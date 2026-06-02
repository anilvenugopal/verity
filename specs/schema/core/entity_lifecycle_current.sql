-- core.entity_lifecycle_current  ·  subject: lifecycle  ·  (view)

CREATE VIEW core.entity_lifecycle_current AS
SELECT DISTINCT ON (executable_version_id)
       executable_version_id, to_state_code AS lifecycle_state_code, created_at AS since
FROM   core.lifecycle_event
ORDER  BY executable_version_id, created_at DESC;
COMMENT ON VIEW core.entity_lifecycle_current IS 'Current lifecycle state per executable_version (latest transition). D4.';
