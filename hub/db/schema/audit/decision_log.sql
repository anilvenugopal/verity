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
COMMENT ON TABLE audit.decision_log IS
'The canonical per-run decision record — the immutable, append-only fact of one AI invocation: inputs, outputs, tool calls, the Source/Target binding resolutions, the frozen inference snapshot, and the full message history. Tier-2 (partitioned by month, BRIN on time) and never an FK target, so it carries SOFT refs to core. run_mode/ab_sample tag A/B runs for champion-vs-challenger comparison (ADR-0004, ADR-0007).

@tier 2
@lifecycle append-only
@subject decisions
@partitioned RANGE(created_at)
@enum audit.decision_status
@adr 0004
@adr 0007';
CREATE INDEX ix_decision_log_version_time ON audit.decision_log (executable_version_id, created_at DESC);
CREATE INDEX brin_decision_log_time ON audit.decision_log USING brin (created_at);
CREATE TABLE audit.decision_log_2026_06 PARTITION OF audit.decision_log FOR VALUES FROM ('2026-06-01') TO ('2026-07-01');
CREATE TABLE audit.decision_log_2026_07 PARTITION OF audit.decision_log FOR VALUES FROM ('2026-07-01') TO ('2026-08-01');
COMMENT ON COLUMN audit.decision_log.decision_log_id IS
'Identity of the decision (with created_at, the partition key); the id the terminal run-status event links to.';
COMMENT ON COLUMN audit.decision_log.executable_version_id IS
'The version that produced the decision; soft ref (Tier-2 is not an FK target). @ref core.executable_version soft';
COMMENT ON COLUMN audit.decision_log.run_id IS
'The run this decision belongs to. @ref core.execution_run soft';
COMMENT ON COLUMN audit.decision_log.decision_status IS
'complete/error/partial outcome of the decision. @enum audit.decision_status';
COMMENT ON COLUMN audit.decision_log.deployment_run_mode_code IS
'live/shadow/ab carried from the run, tagging the decision for A/B comparison. @status reference.deployment_run_mode';
COMMENT ON COLUMN audit.decision_log.ab_sample IS
'A/B sample marker when run_mode=ab.';
COMMENT ON COLUMN audit.decision_log.input_json IS
'The resolved input payload sent to the model.';
COMMENT ON COLUMN audit.decision_log.output_json IS
'The structured output produced.';
COMMENT ON COLUMN audit.decision_log.tool_calls_made IS
'Tool calls the agent made during the decision.';
COMMENT ON COLUMN audit.decision_log.source_resolutions IS
'Which Source Bindings resolved to what, with versions/etags — the input provenance.';
COMMENT ON COLUMN audit.decision_log.target_writes IS
'Which Target Bindings wrote what — the output side effects (suppressed for shadow).';
COMMENT ON COLUMN audit.decision_log.inference_config_snapshot IS
'The frozen inference configuration and resolved model used, so the decision is reproducible.';
COMMENT ON COLUMN audit.decision_log.message_history IS
'The full message history of the invocation.';
COMMENT ON COLUMN audit.decision_log.actor_id IS
'Who the decision is attributed to: the harness automation actor, or a human for a HITL decision (D6). @ref core.actor soft';
COMMENT ON COLUMN audit.decision_log.acting_role_code IS
'The capacity acted in. @status reference.role';
COMMENT ON COLUMN audit.decision_log.request_id IS
'Correlation id for the originating API request.';
COMMENT ON COLUMN audit.decision_log.created_at IS
'When the decision was logged; the partition key. @actor coordinator';
