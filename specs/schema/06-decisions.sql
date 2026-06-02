-- =====================================================================
-- 06-decisions.sql — Verity v2 hardened schema · DECISION/INVOCATION LOGS,
-- the AUDIT (Tier-2) fact stream, evidence, the shared status_transition log,
-- and core MODEL + price. Re-applied per D1 (hot-path enums kept native),
-- D3 (Tier-2 -> audit schema), D4 (append-only + shared transition log),
-- D6 (actor attribution incl. automation actors), ADR-0004/0007/0008.
--
-- Tier-2 audit tables are append-only, RANGE-partitioned by month (BRIN on time),
-- and are NOT FK targets — they carry SOFT uuid references to core (validated at the
-- API layer). Two partitions are shown (2026_06/2026_07); a partition-management job
-- (pg_partman or a CronJob) creates future months ahead of time.
-- =====================================================================

-- ===== native enums kept per D1 (hot-path / Tier-2 internal state) ====
CREATE TYPE audit.decision_status   AS ENUM ('complete', 'error', 'partial');
CREATE TYPE audit.invocation_status AS ENUM ('complete', 'error', 'timeout');
CREATE TYPE audit.auth_event_type   AS ENUM ('login', 'logout', 'session_expiry', 'session_termination', 'authz_denial');
CREATE TYPE audit.auth_event_outcome AS ENUM ('success', 'failure', 'denied');

-- ===== core.model + model_price (SCD-2 pricing) =======================
CREATE TABLE core.model (
    model_id            uuid        NOT NULL DEFAULT uuidv7(),
    model_code          text        NOT NULL,                  -- e.g. 'claude-sonnet-4-6'
    provider            text        NOT NULL,
    modality            text        NOT NULL DEFAULT 'chat',
    model_status_code   text        NOT NULL DEFAULT 'active',
    created_at          timestamptz  NOT NULL DEFAULT now(),
    updated_at          timestamptz  NOT NULL DEFAULT now(),
    CONSTRAINT pk_model PRIMARY KEY (model_id),
    CONSTRAINT fk_model_status FOREIGN KEY (model_status_code) REFERENCES reference.model_status (code),
    CONSTRAINT uq_model_code UNIQUE (model_code));
COMMENT ON TABLE core.model IS 'tier:1. Model registry (identity stable; pricing is SCD-2 in model_price).';

CREATE TABLE core.model_price (
    model_price_id      uuid        NOT NULL DEFAULT uuidv7(),
    model_id            uuid        NOT NULL,
    input_price_per_1k  numeric(12,6) NOT NULL,
    output_price_per_1k numeric(12,6) NOT NULL,
    currency_code       text        NOT NULL DEFAULT 'usd',
    valid_from          timestamptz  NOT NULL DEFAULT now(),
    valid_to            timestamptz,
    created_at          timestamptz  NOT NULL DEFAULT now(),
    CONSTRAINT pk_model_price PRIMARY KEY (model_price_id),
    CONSTRAINT fk_model_price_model FOREIGN KEY (model_id) REFERENCES core.model (model_id) ON DELETE RESTRICT,
    CONSTRAINT fk_model_price_currency FOREIGN KEY (currency_code) REFERENCES reference.currency (code));
COMMENT ON TABLE core.model_price IS 'tier:1 SCD-2. Per-model price windows (valid_from/valid_to). Cost is computed point-in-time, never stored.';
CREATE UNIQUE INDEX uq_model_price_open ON core.model_price (model_id) WHERE valid_to IS NULL;

-- ===== model decoupling: stable reference -> actual model (swappable) =
-- A model_reference is the STABLE alias the registry/inference_config points at (e.g.
-- 'reasoning-primary'). It resolves to an ACTUAL model via an effective-dated binding.
-- Swapping the underlying model = close the binding + open a new one — every package
-- using the reference follows, with NO re-promotion. Past runs resolve as-of (windows).
CREATE TABLE core.model_reference (
    model_reference_id  uuid        NOT NULL DEFAULT uuidv7(),
    reference_code      text        NOT NULL,                  -- stable alias, e.g. 'reasoning-primary'
    name                text        NOT NULL,
    description         text,
    created_at          timestamptz  NOT NULL DEFAULT now(),
    updated_at          timestamptz  NOT NULL DEFAULT now(),
    CONSTRAINT pk_model_reference PRIMARY KEY (model_reference_id),
    CONSTRAINT uq_model_reference_code UNIQUE (reference_code));
COMMENT ON TABLE core.model_reference IS 'tier:1. Stable logical model alias the registry points at; decouples packages from the actual model so it can be swapped centrally without re-promotion (legacy decoupling). Resolves via model_reference_binding.';

CREATE TABLE core.model_reference_binding (
    model_reference_binding_id uuid  NOT NULL DEFAULT uuidv7(),
    model_reference_id  uuid        NOT NULL,
    model_id            uuid        NOT NULL,
    valid_from          timestamptz  NOT NULL DEFAULT now(),
    valid_to            timestamptz,                            -- NULL = current resolution
    reason              text,                                   -- e.g. 'claude-sonnet-4-6 EOL -> claude-sonnet-5'
    bound_by_actor_id   uuid        NOT NULL,
    bound_role_code     text        NOT NULL,
    created_at          timestamptz  NOT NULL DEFAULT now(),
    CONSTRAINT pk_model_reference_binding PRIMARY KEY (model_reference_binding_id),
    CONSTRAINT fk_mrb_reference FOREIGN KEY (model_reference_id) REFERENCES core.model_reference (model_reference_id) ON DELETE RESTRICT,
    CONSTRAINT fk_mrb_model FOREIGN KEY (model_id) REFERENCES core.model (model_id) ON DELETE RESTRICT,
    CONSTRAINT fk_mrb_bound_by FOREIGN KEY (bound_by_actor_id) REFERENCES core.actor (actor_id),
    CONSTRAINT fk_mrb_bound_role FOREIGN KEY (bound_role_code) REFERENCES reference.role (code));
COMMENT ON TABLE core.model_reference_binding IS 'tier:1 SCD-2. Which actual model a reference resolves to, over time. Central swap = close old + open new (NO package re-promotion); windows allow as-of resolution for past runs.';
CREATE UNIQUE INDEX uq_model_reference_binding_current ON core.model_reference_binding (model_reference_id) WHERE valid_to IS NULL;

-- executable-level FALLBACK chain: an inference_config uses an ORDERED list of references.
CREATE TABLE core.inference_config_model (
    inference_config_id uuid        NOT NULL,
    model_reference_id  uuid        NOT NULL,
    priority            integer      NOT NULL,                  -- 1 = primary; 2,3… = fallbacks (tried in order)
    CONSTRAINT pk_inference_config_model PRIMARY KEY (inference_config_id, priority),
    CONSTRAINT fk_icm_config FOREIGN KEY (inference_config_id) REFERENCES core.inference_config (inference_config_id) ON DELETE CASCADE,
    CONSTRAINT fk_icm_reference FOREIGN KEY (model_reference_id) REFERENCES core.model_reference (model_reference_id) ON DELETE RESTRICT,
    CONSTRAINT uq_inference_config_model_ref UNIQUE (inference_config_id, model_reference_id),
    CONSTRAINT ck_inference_config_model_priority CHECK (priority >= 1));
COMMENT ON TABLE core.inference_config_model IS 'tier:1. The ordered model_references an executable_version uses: priority 1 = primary, 2+ = fallbacks. Per-executable fallback (D): the harness tries the next reference when a provider is unavailable/errors. Each reference resolves to an actual model via its current binding.';

-- ===== AUDIT (Tier-2): decision log ===================================
CREATE TABLE audit.decision_log (
    decision_log_id        uuid        NOT NULL DEFAULT uuidv7(),
    executable_version_id  uuid,                                 -- soft ref -> core (Tier-2 not an FK target)
    run_id                 uuid,                                 -- soft ref -> runtime.execution_run (07)
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

-- ===== AUDIT (Tier-2): model-invocation log + cost view ===============
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

-- cost = tokens × the price in effect at invocation time (joins model_price by window)
CREATE VIEW audit.v_model_invocation_cost AS
SELECT m.model_invocation_log_id, m.created_at, m.model_id,
       m.input_tokens, m.output_tokens,
       round((m.input_tokens  / 1000.0) * p.input_price_per_1k
           + (m.output_tokens / 1000.0) * p.output_price_per_1k, 6) AS cost,
       p.currency_code
FROM   audit.model_invocation_log m
LEFT   JOIN core.model_price p
       ON p.model_id = m.model_id
      AND m.created_at >= p.valid_from
      AND (p.valid_to IS NULL OR m.created_at < p.valid_to);
COMMENT ON VIEW audit.v_model_invocation_cost IS 'Point-in-time cost: tokens × price-in-effect-at-invocation (SCD-2 join on model_price window). Stable across later price edits.';

-- ===== AUDIT (Tier-2): evidence fact stream (deferred from 05) =========
CREATE TABLE audit.evidence (
    evidence_id            uuid       NOT NULL DEFAULT uuidv7(),
    canonical_requirement_id uuid,                               -- soft refs -> compliance (core), pinned versions
    requirement_tier_id    uuid,
    control_id             uuid,
    evidence_specification_id uuid,
    control_phase_code     text,                                 -- design_time|deploy_time|static_model|execution
    evidence_artifact_type_code text,
    executable_version_id  uuid,                                 -- what produced it (soft)
    run_id                 uuid,                                 -- soft -> execution_run
    decision_log_id        uuid,                                 -- soft -> decision_log
    storage_ref            jsonb,                                -- where the artifact lives (connector + locator + digest)
    produced_by_actor_id   uuid       NOT NULL,                  -- AUTOMATION (auto-captured) or human (attested) — D6
    produced_role_code     text       NOT NULL,
    created_at             timestamptz NOT NULL DEFAULT now(),
    CONSTRAINT pk_evidence PRIMARY KEY (evidence_id, created_at)
) PARTITION BY RANGE (created_at);
COMMENT ON TABLE audit.evidence IS 'tier:2 append-only (partitioned). The compliance evidence FACT stream (vs evidence_specification = the spec). Tied to requirement+tier+phase+entity/run. produced_by an actor (automation for auto-captured). ADR-0008.';
CREATE INDEX ix_evidence_requirement_time ON audit.evidence (canonical_requirement_id, created_at DESC);
CREATE INDEX brin_evidence_time ON audit.evidence USING brin (created_at);
CREATE TABLE audit.evidence_2026_06 PARTITION OF audit.evidence FOR VALUES FROM ('2026-06-01') TO ('2026-07-01');
CREATE TABLE audit.evidence_2026_07 PARTITION OF audit.evidence FOR VALUES FROM ('2026-07-01') TO ('2026-08-01');

-- ===== AUDIT (Tier-2): shared status_transition log (D4) ==============
-- Every mutable *_status_code change across the schema is appended here — ONE uniform
-- history for intake/requirement/plan/approval/exception/roi-lock/deployment/etc.
CREATE TABLE audit.status_transition (
    status_transition_id uuid        NOT NULL DEFAULT uuidv7(),
    entity_type          text        NOT NULL,                  -- 'intake' | 'approval_request' | 'compliance_exception' | …
    entity_id            uuid        NOT NULL,                  -- soft ref to the core row
    status_field         text        NOT NULL DEFAULT 'status', -- which coded field changed (e.g. intake_status_code)
    from_code            text,
    to_code              text        NOT NULL,
    actor_id             uuid        NOT NULL,
    acting_role_code     text        NOT NULL,
    reason               text,
    created_at           timestamptz  NOT NULL DEFAULT now(),
    CONSTRAINT pk_status_transition PRIMARY KEY (status_transition_id, created_at)
) PARTITION BY RANGE (created_at);
COMMENT ON TABLE audit.status_transition IS 'tier:2 append-only (partitioned). The ONE shared transition log for every mutable *_status_code in the schema (D4). entity_type + entity_id are soft refs.';
CREATE INDEX ix_status_transition_entity ON audit.status_transition (entity_type, entity_id, created_at DESC);
CREATE TABLE audit.status_transition_2026_06 PARTITION OF audit.status_transition FOR VALUES FROM ('2026-06-01') TO ('2026-07-01');
CREATE TABLE audit.status_transition_2026_07 PARTITION OF audit.status_transition FOR VALUES FROM ('2026-07-01') TO ('2026-08-01');

-- ===== AUDIT (Tier-2): auth_event (from the auth spec) ================
CREATE TABLE audit.auth_event (
    auth_event_id    uuid        NOT NULL DEFAULT uuidv7(),
    event_type       audit.auth_event_type    NOT NULL,
    outcome          audit.auth_event_outcome NOT NULL,
    reason_code      text,                                       -- bad_signature|expired|nonce_mismatch|unknown_tenant|mock_auth|…
    actor_id         uuid,                                        -- nullable (pre-identity failures)
    action_code      text,
    resource         text,
    request_id       text        NOT NULL,
    ip               inet,
    created_at       timestamptz  NOT NULL DEFAULT now(),
    CONSTRAINT pk_auth_event PRIMARY KEY (auth_event_id, created_at)
) PARTITION BY RANGE (created_at);
COMMENT ON TABLE audit.auth_event IS 'tier:2 append-only (partitioned). Authentication/authorization events (login/logout/denial). user-authentication.md FR-024.';
CREATE INDEX ix_auth_event_actor_time ON audit.auth_event (actor_id, created_at DESC);
CREATE TABLE audit.auth_event_2026_06 PARTITION OF audit.auth_event FOR VALUES FROM ('2026-06-01') TO ('2026-07-01');
CREATE TABLE audit.auth_event_2026_07 PARTITION OF audit.auth_event FOR VALUES FROM ('2026-07-01') TO ('2026-08-01');

-- ===== core.hitl_override (human override of a decision; append-only) =
CREATE TABLE core.hitl_override (
    hitl_override_id    uuid        NOT NULL DEFAULT uuidv7(),
    decision_log_id     uuid        NOT NULL,                   -- soft ref -> audit.decision_log (Tier-2)
    field_path          text        NOT NULL,
    original_value      jsonb,
    override_value      jsonb       NOT NULL,
    reason              text        NOT NULL,
    actor_id            uuid        NOT NULL,                   -- the human (D6)
    acting_role_code    text        NOT NULL,
    created_at          timestamptz  NOT NULL DEFAULT now(),
    CONSTRAINT pk_hitl_override PRIMARY KEY (hitl_override_id),
    CONSTRAINT fk_hitl_override_actor FOREIGN KEY (actor_id) REFERENCES core.actor (actor_id),
    CONSTRAINT fk_hitl_override_acting_role FOREIGN KEY (acting_role_code) REFERENCES reference.role (code));
COMMENT ON TABLE core.hitl_override IS 'tier:1 append-only. Per-field human override on a decision (soft ref to the Tier-2 decision_log). Attributed to the human actor. D6.';

-- ===== wire deferred FKs from earlier domains =========================
-- (inference_config no longer hard-pins a model — it uses model_references via
--  inference_config_model above; nothing to wire for it.)
-- The cost ESTIMATE still references a concrete model for pricing (it is a forecast,
-- not a promoted/packaged artifact), so it keeps a direct model_id.
ALTER TABLE core.intake_artifact_plan_estimate
    ADD CONSTRAINT fk_intake_estimate_model FOREIGN KEY (model_id) REFERENCES core.model (model_id) ON DELETE RESTRICT;
ALTER TABLE core.intake_cost_envelope
    ADD CONSTRAINT fk_intake_cost_currency FOREIGN KEY (currency_code) REFERENCES reference.currency (code);
