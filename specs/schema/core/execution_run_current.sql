-- core.execution_run_current  ·  subject: runs  ·  (view)

CREATE VIEW core.execution_run_current AS
SELECT DISTINCT ON (execution_run_id)
       execution_run_id, run_status_code, completion_status_code, worker_instance_id, worker_node_id, decision_log_id, error_code, created_at AS as_of
FROM   core.execution_run_status
ORDER  BY execution_run_id, created_at DESC;
COMMENT ON VIEW core.execution_run_current IS
'The live current-state projection over execution_run_status (the latest event per run).
The status API and the SSE polling fallback read this view, never the Tier-2 analytics
store, so "what is this run doing now" is always answered from the system of record
(PCR §3.4, ADR-0007).

@tier 1
@lifecycle view
@subject runs
@adr 0007';
