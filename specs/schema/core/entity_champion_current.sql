-- core.entity_champion_current  ·  subject: lifecycle  ·  (view)

-- current champion version per executable (resolved via the version's executable_id)
CREATE VIEW core.entity_champion_current AS
SELECT executable_id, executable_version_id
FROM (
    SELECT DISTINCT ON (ev.executable_id)
           ev.executable_id, ca.executable_version_id, ca.is_revocation
    FROM   core.champion_assignment ca
    JOIN   core.executable_version ev ON ev.executable_version_id = ca.executable_version_id
    ORDER  BY ev.executable_id, ca.created_at DESC
) latest
WHERE NOT is_revocation;
COMMENT ON VIEW core.entity_champion_current IS 'Current champion executable_version per executable (latest non-revoked assignment). D4.';
