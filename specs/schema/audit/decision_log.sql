-- audit.decision_log  ·  subject: decisions  ·  (table)

CREATE TABLE audit.decision_log (
    decision_log_id        uuid        NOT NULL DEFAULT uuidv7(),
    executable_version_id  uuid,                                 -- soft ref -> core (Tier-2 not an FK target)
    run_id                 uuid,                                 -- soft ref -> core.execution_run (07)
    decision_status        audit.decision_status NOT NULL,
    deployment_run_mode_code text,                               -- live|shadow|ab (tag for A/B comparison)
    ab_sample              text,                                  -- A/B sample scope marker (when run_mode=ab)
    input_json             jsonb,
    output_json            jsonb,
    tool_calls_made        jsonb,
    source_resolutions     jsonb,                                -- which Source Bindings resolved to what (+ versions/etags)
    target_writes          jsonb,                                -- which Target Bindings wrote what
    inference_config_snapshot jsonb,
    message_history        jsonb,
    actor_id               uuid        NOT NULL,                 -- the AUTOMATION actor (harness) or human (HITL) — D6
    acting_role_code       text        NOT NULL,
    request_id             text,
    created_at             timestamptz  NOT NULL DEFAULT now(),
    CONSTRAINT pk_decision_log PRIMARY KEY (decision_log_id, created_at)
) PARTITION BY RANGE (created_at);
COMMENT ON TABLE audit.decision_log IS 'tier:2 append-only (partitioned). The canonical per-run decision record. Soft refs to core. ab_sample/run_mode tag A/B runs for champion-vs-challenger. ADR-0004/0007.';
CREATE INDEX ix_decision_log_version_time ON audit.decision_log (executable_version_id, created_at DESC);
CREATE INDEX brin_decision_log_time ON audit.decision_log USING brin (created_at);
CREATE TABLE audit.decision_log_2026_06 PARTITION OF audit.decision_log FOR VALUES FROM ('2026-06-01') TO ('2026-07-01');
CREATE TABLE audit.decision_log_2026_07 PARTITION OF audit.decision_log FOR VALUES FROM ('2026-07-01') TO ('2026-08-01');
