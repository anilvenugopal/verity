-- audit.harness_instance_health_current  ·  subject: deploy  ·  (view)

CREATE VIEW audit.harness_instance_health_current AS
SELECT DISTINCT ON (harness_instance_id)
       harness_instance_id, health_status_code, running_image_digest, created_at AS last_seen
FROM   audit.harness_heartbeat
ORDER  BY harness_instance_id, created_at DESC;
COMMENT ON VIEW audit.harness_instance_health_current IS
'Latest health per instance from the heartbeat stream — the fast "who is up or down, and on what image" projection the portal dashboard reads without scanning the Tier-2 partitions.

@tier 2
@lifecycle view
@subject deploy
@decision D8';
