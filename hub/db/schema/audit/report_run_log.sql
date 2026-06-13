-- audit.report_run_log  ·  subject: reporting  ·  (table)

CREATE TABLE audit.report_run_log (
    report_run_log_id    uuid        NOT NULL DEFAULT uuidv7(),
    report_definition_id uuid,                                   -- soft ref -> core.report_definition
    report_run_status_code text      NOT NULL,                  -- pending|succeeded|failed
    requested_by_actor_id uuid       NOT NULL,
    parameters           jsonb,
    output_ref           jsonb,                                  -- where the rendered report landed (storage)
    error                text,
    started_at           timestamptz,
    finished_at          timestamptz,
    created_at           timestamptz  NOT NULL DEFAULT now(),
    CONSTRAINT pk_report_run_log PRIMARY KEY (report_run_log_id, created_at)
) PARTITION BY RANGE (created_at);
COMMENT ON TABLE audit.report_run_log IS
'Append-only log of async report-job runs — status, parameters, where the rendered output landed, timings, and errors. Tier-2, partitioned. The canonical analytics store is EXTERNAL (Iceberg/Parquet, customer-portable); this is only the local run log (ADR-0007).

@tier 2
@lifecycle append-only
@subject reporting
@partitioned RANGE(created_at)
@status reference.report_run_status
@adr 0007';
CREATE INDEX ix_report_run_log_definition_time ON audit.report_run_log (report_definition_id, created_at DESC);
CREATE TABLE audit.report_run_log_2026_06 PARTITION OF audit.report_run_log FOR VALUES FROM ('2026-06-01') TO ('2026-07-01');
CREATE TABLE audit.report_run_log_2026_07 PARTITION OF audit.report_run_log FOR VALUES FROM ('2026-07-01') TO ('2026-08-01');
COMMENT ON COLUMN audit.report_run_log.report_run_log_id IS
'Identity of the run (with created_at, the partition key).';
COMMENT ON COLUMN audit.report_run_log.report_definition_id IS
'The report that was run. @ref core.report_definition soft';
COMMENT ON COLUMN audit.report_run_log.report_run_status_code IS
'pending/succeeded/failed. @status reference.report_run_status';
COMMENT ON COLUMN audit.report_run_log.requested_by_actor_id IS
'Who requested the run. @ref core.actor soft';
COMMENT ON COLUMN audit.report_run_log.parameters IS
'Run parameters.';
COMMENT ON COLUMN audit.report_run_log.output_ref IS
'Where the rendered report landed (storage).';
COMMENT ON COLUMN audit.report_run_log.error IS
'Failure detail, if any.';
COMMENT ON COLUMN audit.report_run_log.started_at IS
'When the job started.';
COMMENT ON COLUMN audit.report_run_log.finished_at IS
'When the job finished.';
COMMENT ON COLUMN audit.report_run_log.created_at IS
'When the run was enqueued; the partition key.';
