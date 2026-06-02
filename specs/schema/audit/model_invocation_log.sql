-- audit.model_invocation_log  ·  subject: decisions  ·  (table)

CREATE TABLE audit.model_invocation_log (
    model_invocation_log_id uuid     NOT NULL DEFAULT uuidv7(),
    decision_log_id        uuid,                                 -- soft ref -> decision_log
    model_id               uuid,                                 -- soft ref -> core.model
    invocation_status      audit.invocation_status NOT NULL,
    input_tokens           integer,
    output_tokens          integer,
    duration_ms            integer,
    created_at             timestamptz  NOT NULL DEFAULT now(),
    CONSTRAINT pk_model_invocation_log PRIMARY KEY (model_invocation_log_id, created_at)
) PARTITION BY RANGE (created_at);
COMMENT ON TABLE audit.model_invocation_log IS 'tier:2 append-only (partitioned). Per-model-call token usage. Cost computed point-in-time via v_model_invocation_cost (never stored).';
CREATE INDEX brin_model_invocation_log_time ON audit.model_invocation_log USING brin (created_at);
CREATE TABLE audit.model_invocation_log_2026_06 PARTITION OF audit.model_invocation_log FOR VALUES FROM ('2026-06-01') TO ('2026-07-01');
CREATE TABLE audit.model_invocation_log_2026_07 PARTITION OF audit.model_invocation_log FOR VALUES FROM ('2026-07-01') TO ('2026-08-01');
