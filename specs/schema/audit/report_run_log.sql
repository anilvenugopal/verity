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
COMMENT ON TABLE audit.report_run_log IS 'tier:2 append-only (partitioned). Async report-job runs. The canonical analytics store is EXTERNAL (Iceberg/Parquet, customer-portable) — ADR-0007.';
CREATE INDEX ix_report_run_log_definition_time ON audit.report_run_log (report_definition_id, created_at DESC);
CREATE TABLE audit.report_run_log_2026_06 PARTITION OF audit.report_run_log FOR VALUES FROM ('2026-06-01') TO ('2026-07-01');
CREATE TABLE audit.report_run_log_2026_07 PARTITION OF audit.report_run_log FOR VALUES FROM ('2026-07-01') TO ('2026-08-01');
