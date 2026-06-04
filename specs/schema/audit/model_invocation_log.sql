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
COMMENT ON TABLE audit.model_invocation_log IS
'Per-model-call token usage for a decision (one decision may make several calls). Tier-2, partitioned by month. Token counts only — cost is computed point-in-time via v_model_invocation_cost, never stored.

@tier 2
@lifecycle append-only
@subject decisions
@partitioned RANGE(created_at)
@enum audit.invocation_status';
CREATE INDEX brin_model_invocation_log_time ON audit.model_invocation_log USING brin (created_at);
CREATE TABLE audit.model_invocation_log_2026_06 PARTITION OF audit.model_invocation_log FOR VALUES FROM ('2026-06-01') TO ('2026-07-01');
CREATE TABLE audit.model_invocation_log_2026_07 PARTITION OF audit.model_invocation_log FOR VALUES FROM ('2026-07-01') TO ('2026-08-01');
COMMENT ON COLUMN audit.model_invocation_log.model_invocation_log_id IS
'Identity of the invocation record (with created_at, the partition key).';
COMMENT ON COLUMN audit.model_invocation_log.decision_log_id IS
'The decision this call served. @ref audit.decision_log soft';
COMMENT ON COLUMN audit.model_invocation_log.model_id IS
'The model actually called (resolved from the reference). @ref core.model soft';
COMMENT ON COLUMN audit.model_invocation_log.invocation_status IS
'complete/error/timeout. @enum audit.invocation_status';
COMMENT ON COLUMN audit.model_invocation_log.input_tokens IS
'Input token count; multiplied by the as-of price for cost.';
COMMENT ON COLUMN audit.model_invocation_log.output_tokens IS
'Output token count; multiplied by the as-of price for cost.';
COMMENT ON COLUMN audit.model_invocation_log.duration_ms IS
'Call latency in milliseconds.';
COMMENT ON COLUMN audit.model_invocation_log.created_at IS
'When the call completed; the partition key.';
