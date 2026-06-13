-- audit.harness_running_package_current  ·  subject: deploy  ·  (view)

CREATE VIEW audit.harness_running_package_current AS
SELECT DISTINCT ON (harness_instance_id)
       harness_instance_id, running_packages, created_at AS as_of
FROM   audit.harness_heartbeat
WHERE  heartbeat_kind_code = 'major'
ORDER  BY harness_instance_id, created_at DESC;
COMMENT ON VIEW audit.harness_running_package_current IS
'Latest running-package catalog per instance, taken from major heartbeats. Compared against core.deployment to surface deployment drift — what is actually running versus what governance says should be (D8).

@tier 2
@lifecycle view
@subject deploy
@decision D8';
