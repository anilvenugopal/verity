-- audit.harness_instance_health_current  ·  subject: deploy  ·  (view)

CREATE VIEW audit.harness_instance_health_current AS
SELECT DISTINCT ON (harness_instance_id)
       harness_instance_id, health_status_code, running_image_digest, created_at AS last_seen
FROM   audit.harness_heartbeat
ORDER  BY harness_instance_id, created_at DESC;
