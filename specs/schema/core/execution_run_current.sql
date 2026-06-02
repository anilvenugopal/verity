-- core.execution_run_current  ·  subject: runs  ·  (view)

CREATE VIEW core.execution_run_current AS
SELECT DISTINCT ON (execution_run_id)
       execution_run_id, run_status, completion_status, worker_instance_id, decision_log_id, error_code, created_at AS as_of
FROM   core.execution_run_status
ORDER  BY execution_run_id, created_at DESC;
COMMENT ON VIEW core.execution_run_current IS 'Current state per run (latest status event). The status path reads this view, never the analytics tier (PCR §3.4).';
