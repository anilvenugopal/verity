-- 06-decisions.sql — hardened v2 schema domain: decisions
-- See ASSEMBLY-AND-VERIFICATION.md for cross-domain FKs & review items.

-- =============================================================================
-- DOMAIN: DECISION & MODEL-INVOCATION LOGGING + HITL
-- v2 hardened DDL (ADR-0004 / ADR-0005 / ADR-0007). Schema: governance.
-- Conventions: snake_case, singular tables, surrogate <table>_id uuid DEFAULT
-- uuidv7(), named pk_/fk_/uq_/ck_/ix_/brin_ constraints, enum types, timestamptz,
-- append-only logs, Tier-2 range-partitioned on created_at with BRIN.
--
-- TIERING:
--   Tier-2 (bulk append-only log, partitioned + BRIN): agent_decision_log,
--           model_invocation_log.
--   Tier-1 (system-of-record, thin Postgres): model, model_price (SCD-2),
--           hitl_override (per-field override audit fact).
--
-- CROSS-TIER / CROSS-DOMAIN FK POLICY: a Tier-2 partitioned log table is NOT a
-- safe FK target (composite PK includes the partition key; cross-tier referential
-- integrity is not enforced per ADR-0004 — the analytics tier is never in the
-- write path). References INTO Tier-2 logs (and references owned by OTHER domains:
-- governance.user, governance.execution_run, governance.agent_version,
-- governance.approval/intake) are therefore declared as documented SOFT references
-- (plain uuid columns, app-validated), NOT DB FKs. They are listed in open_issues.
-- =============================================================================

-- Idempotency note: uuidv7() requires PostgreSQL 18+. On PG < 18, define a
-- fallback wrapper that delegates to gen_random_uuid() with the SAME name
-- (CREATE FUNCTION governance.uuidv7() ... RETURNS uuid) so column defaults are
-- portable; this is documented in the schema preamble, not redefined per domain.

-- -----------------------------------------------------------------------------
-- ENUM TYPES (controlled vocabularies — preserved verbatim from v1 contracts)
-- -----------------------------------------------------------------------------

-- v1 governance.entity_type members agent/task/prompt/tool; decision log uses the
-- subset agent/task/tool (enforced by ck_agent_decision_log_entity_type_known).
-- The full entity_type enum is OWNED by the registry domain; referenced here.
-- DO $$ BEGIN ... (declared once in the registry domain):
-- CREATE TYPE governance.entity_type AS ENUM ('agent','task','prompt','tool');

-- run_purpose: verbatim from v1 governance.run_purpose.
CREATE TYPE governance.run_purpose AS ENUM (
    'production',
    'test',
    'validation',
    'audit_rerun'
);
COMMENT ON TYPE governance.run_purpose IS
    'Verbatim v1 controlled vocabulary: why a decision was produced.';

-- Decision-log lifecycle status for the captured terminal fact (v1 used a free
-- varchar default ''complete''). Hardened to an enum.
CREATE TYPE governance.decision_status AS ENUM (
    'complete',
    'error',
    'partial'
);
COMMENT ON TYPE governance.decision_status IS
    'Terminal status captured on an immutable decision-log row.';

-- Decision-log detail level (v1 free varchar ''standard'').
CREATE TYPE governance.decision_log_detail AS ENUM (
    'minimal',
    'standard',
    'full'
);

-- Model-invocation status (v1 free varchar ''complete'').
CREATE TYPE governance.invocation_status AS ENUM (
    'complete',
    'error',
    'timeout'
);

-- Model lifecycle status (v1 model.status free varchar ''active'').
CREATE TYPE governance.model_status AS ENUM (
    'active',
    'deprecated',
    'retired'
);

-- Currency code (v1 model_price.currency varchar(3) default ''USD''). Kept as a
-- small enum of supported settlement currencies; extend additively.
CREATE TYPE governance.currency_code AS ENUM (
    'usd',
    'eur',
    'gbp'
);


-- =============================================================================
-- TIER-1: MODEL CATALOG + SCD-2 PRICE CATALOG
-- =============================================================================

-- governance.model — provider model registry (Tier-1, system-of-record).
-- v1 governance.model: KEEP (rehardened). Mutable registry row (status changes).
CREATE TABLE governance.model (
    model_id        uuid                     NOT NULL DEFAULT governance.uuidv7(),
    provider        text                     NOT NULL,
    provider_model_id text                   NOT NULL,   -- v1 model.model_id (renamed; was a natural id, not surrogate)
    display_name    text                     NOT NULL,
    modality        text                     NOT NULL DEFAULT 'chat',
    context_window  integer,
    status          governance.model_status  NOT NULL DEFAULT 'active',
    description     text,
    created_at      timestamptz              NOT NULL DEFAULT now(),
    updated_at      timestamptz              NOT NULL DEFAULT now(),
    CONSTRAINT pk_model PRIMARY KEY (model_id),
    CONSTRAINT uq_model_provider_model UNIQUE (provider, provider_model_id),
    CONSTRAINT ck_model_context_window_positive
        CHECK (context_window IS NULL OR context_window > 0)
);
COMMENT ON TABLE  governance.model IS
    'tier:1 system-of-record. Provider model registry. Mutable (status/display).';
COMMENT ON COLUMN governance.model.provider_model_id IS
    'Renamed from v1 model.model_id (a natural key) to avoid colliding with the surrogate <table>_id convention; the surrogate PK is model_id.';

CREATE INDEX ix_model_provider ON governance.model (provider);
CREATE INDEX ix_model_status   ON governance.model (status);

-- governance.model_price — SCD-2 temporal price catalog (Tier-1, APPEND-ONLY).
-- v1 governance.model_price: KEEP (rehardened to explicit SCD-2 / append-only).
-- A price change is a NEW row: close the prior row (set valid_to) and insert the
-- new open row. Current price = the row with valid_to IS NULL (or whose
-- [valid_from, valid_to) window contains the lookup instant). Cost is computed
-- point-in-time by joining a log row's instant into this window (see view below);
-- cost is NEVER stored.
CREATE TABLE governance.model_price (
    model_price_id            uuid                    NOT NULL DEFAULT governance.uuidv7(),
    model_id                  uuid                    NOT NULL,
    input_price_per_1m        numeric(14,6)           NOT NULL,
    output_price_per_1m       numeric(14,6)           NOT NULL,
    cache_read_price_per_1m   numeric(14,6),
    cache_write_price_per_1m  numeric(14,6),
    currency                  governance.currency_code NOT NULL DEFAULT 'usd',
    valid_from                timestamptz             NOT NULL,
    valid_to                  timestamptz,            -- NULL => current/open row
    notes                     text,
    created_at                timestamptz             NOT NULL DEFAULT now(),
    CONSTRAINT pk_model_price PRIMARY KEY (model_price_id),
    CONSTRAINT fk_model_price_model
        FOREIGN KEY (model_id) REFERENCES governance.model (model_id)
        ON DELETE RESTRICT,
    CONSTRAINT ck_model_price_window
        CHECK (valid_to IS NULL OR valid_to > valid_from),
    CONSTRAINT ck_model_price_input_nonneg
        CHECK (input_price_per_1m >= 0),
    CONSTRAINT ck_model_price_output_nonneg
        CHECK (output_price_per_1m >= 0),
    CONSTRAINT ck_model_price_cache_read_nonneg
        CHECK (cache_read_price_per_1m IS NULL OR cache_read_price_per_1m >= 0),
    CONSTRAINT ck_model_price_cache_write_nonneg
        CHECK (cache_write_price_per_1m IS NULL OR cache_write_price_per_1m >= 0)
);
COMMENT ON TABLE governance.model_price IS
    'tier:1 system-of-record, append-only SCD-2. One row per price period; valid_to NULL = current. Price change = close prior row + insert new open row. Cost computed point-in-time, never stored.';

-- At most one OPEN (current) price row per model — the SCD-2 invariant.
CREATE UNIQUE INDEX uq_model_price_open_per_model
    ON governance.model_price (model_id)
    WHERE valid_to IS NULL;
-- Point-in-time lookup support (model + period).
CREATE INDEX ix_model_price_model_valid_from
    ON governance.model_price (model_id, valid_from DESC);


-- =============================================================================
-- TIER-2: AGENT DECISION LOG (append-only, month range-partitioned, BRIN)
-- =============================================================================

-- governance.agent_decision_log — canonical immutable audit record of one entity
-- decision. v1 runtime.agent_decision_log: KEEP (moved runtime -> governance,
-- rehardened to Tier-2 append-only + partitioned). One row per decision; the row
-- IS the terminal fact (status captured on it). No UPDATE/DELETE.
--
-- Partitioned tables require the partition key in every UNIQUE/PK constraint, so
-- PK is (agent_decision_log_id, created_at). agent_decision_log_id alone remains
-- globally unique by construction (uuidv7).
CREATE TABLE governance.agent_decision_log (
    agent_decision_log_id     uuid                          NOT NULL DEFAULT governance.uuidv7(),
    -- WHAT produced the decision
    entity_type               governance.entity_type        NOT NULL,
    entity_version_id         uuid                          NOT NULL,  -- soft ref -> registry version (cross-domain)
    prompt_version_ids        uuid[]                        NOT NULL DEFAULT '{}',
    inference_config_snapshot jsonb                         NOT NULL,
    channel                   text                          NOT NULL,  -- deployment channel value (enum owned by registry/lifecycle domain)
    mock_mode                 boolean                       NOT NULL DEFAULT false,
    run_purpose               governance.run_purpose        NOT NULL DEFAULT 'production',
    -- run / workflow linkage (soft refs — see open_issues)
    workflow_run_id           uuid,
    execution_run_id          uuid,                                    -- soft ref -> governance.execution_run (run domain)
    parent_decision_id        uuid,                                    -- soft ref -> self (Tier-2, cannot FK across partitions)
    reproduced_from_decision_id uuid,                                  -- soft ref -> self
    execution_context_id      uuid,                                    -- soft ref -> run domain
    decision_depth            integer                       NOT NULL DEFAULT 0,
    step_name                 text,
    -- captured I/O and reasoning
    input_summary             text,
    input_json                jsonb,
    output_json               jsonb,
    output_summary            text,
    reasoning_text            text,
    risk_factors              jsonb,
    confidence_score          numeric(5,4),
    low_confidence_flag       boolean                       NOT NULL DEFAULT false,
    -- model usage rollup (authoritative per-call detail is in model_invocation_log)
    model_used                text,
    input_tokens              integer,
    output_tokens             integer,
    duration_ms               integer,
    tool_calls_made           jsonb,
    message_history           jsonb,
    -- v2 binding-grammar capture (renamed from v1 source_resolutions / target_writes)
    source_binding_resolutions jsonb,
    target_binding_writes      jsonb,
    redaction_applied         jsonb,
    application                text                          NOT NULL DEFAULT 'default',
    -- HITL linkage (per-field overrides live in governance.hitl_override)
    hitl_required             boolean                       NOT NULL DEFAULT false,
    hitl_completed            boolean                       NOT NULL DEFAULT false,
    hitl_approval_id          uuid,                                    -- soft ref -> approval domain
    -- terminal status of this decision
    status                    governance.decision_status    NOT NULL DEFAULT 'complete',
    error_message             text,
    decision_log_detail       governance.decision_log_detail NOT NULL DEFAULT 'standard',
    created_at                timestamptz                   NOT NULL DEFAULT now(),
    CONSTRAINT pk_agent_decision_log
        PRIMARY KEY (agent_decision_log_id, created_at),
    CONSTRAINT ck_agent_decision_log_entity_type_known
        CHECK (entity_type IN ('agent','task','tool')),
    CONSTRAINT ck_agent_decision_log_depth_nonneg
        CHECK (decision_depth >= 0),
    CONSTRAINT ck_agent_decision_log_confidence_range
        CHECK (confidence_score IS NULL OR (confidence_score >= 0 AND confidence_score <= 1)),
    CONSTRAINT ck_agent_decision_log_tokens_nonneg
        CHECK ((input_tokens  IS NULL OR input_tokens  >= 0)
           AND (output_tokens IS NULL OR output_tokens >= 0)),
    CONSTRAINT ck_agent_decision_log_error_requires_message
        CHECK (status <> 'error' OR error_message IS NOT NULL)
) PARTITION BY RANGE (created_at);
COMMENT ON TABLE governance.agent_decision_log IS
    'tier:2 bulk-log append-only. Canonical immutable audit record, one row per decision. Range-partitioned by month on created_at; BRIN on created_at. No UPDATE/DELETE. Self/run/approval refs are soft (app-validated) — Tier-2 is not an FK target.';
COMMENT ON COLUMN governance.agent_decision_log.source_binding_resolutions IS
    'v2 rename of v1 source_resolutions (binding-grammar: Source Binding capture).';
COMMENT ON COLUMN governance.agent_decision_log.target_binding_writes IS
    'v2 rename of v1 target_writes (binding-grammar: Target Binding capture).';

CREATE INDEX brin_agent_decision_log_created_at
    ON governance.agent_decision_log USING brin (created_at);
CREATE INDEX ix_agent_decision_log_entity
    ON governance.agent_decision_log (entity_type, entity_version_id);
CREATE INDEX ix_agent_decision_log_execution_run
    ON governance.agent_decision_log (execution_run_id);
CREATE INDEX ix_agent_decision_log_workflow_run
    ON governance.agent_decision_log (workflow_run_id);
CREATE INDEX ix_agent_decision_log_parent
    ON governance.agent_decision_log (parent_decision_id);

-- Initial monthly partition (one per month; created ahead by an ops/cron job).
CREATE TABLE governance.agent_decision_log_2026_05
    PARTITION OF governance.agent_decision_log
    FOR VALUES FROM ('2026-05-01') TO ('2026-06-01');
CREATE TABLE governance.agent_decision_log_2026_06
    PARTITION OF governance.agent_decision_log
    FOR VALUES FROM ('2026-06-01') TO ('2026-07-01');


-- =============================================================================
-- TIER-2: MODEL INVOCATION LOG (append-only, month range-partitioned, BRIN)
-- =============================================================================

-- governance.model_invocation_log — per-LLM-call usage record (Tier-2, append-only).
-- v1 runtime.model_invocation_log: KEEP (runtime -> governance, rehardened).
-- decision_log_id is a SOFT ref (the decision log is Tier-2/partitioned — not an
-- FK target; v1's ON DELETE CASCADE is dropped: append-only logs are never deleted).
CREATE TABLE governance.model_invocation_log (
    model_invocation_log_id      uuid                        NOT NULL DEFAULT governance.uuidv7(),
    decision_log_id              uuid                        NOT NULL,  -- soft ref -> agent_decision_log (Tier-2)
    model_id                     uuid                        NOT NULL,  -- soft ref -> governance.model (Tier-1; not FK'd to keep Tier-2 write path decoupled)
    provider                     text                        NOT NULL,
    model_name                   text                        NOT NULL,
    started_at                   timestamptz                 NOT NULL,
    completed_at                 timestamptz                 NOT NULL,
    input_tokens                 integer                     NOT NULL DEFAULT 0,
    output_tokens                integer                     NOT NULL DEFAULT 0,
    cache_creation_input_tokens  integer                     NOT NULL DEFAULT 0,
    cache_read_input_tokens      integer                     NOT NULL DEFAULT 0,
    api_call_count               integer                     NOT NULL DEFAULT 1,
    stop_reason                  text,
    status                       governance.invocation_status NOT NULL DEFAULT 'complete',
    error_message                text,
    per_turn_metadata            jsonb,
    created_at                   timestamptz                 NOT NULL DEFAULT now(),
    CONSTRAINT pk_model_invocation_log
        PRIMARY KEY (model_invocation_log_id, created_at),
    CONSTRAINT ck_model_invocation_log_completed_after_started
        CHECK (completed_at >= started_at),
    CONSTRAINT ck_model_invocation_log_tokens_nonneg
        CHECK (input_tokens >= 0 AND output_tokens >= 0
           AND cache_creation_input_tokens >= 0 AND cache_read_input_tokens >= 0),
    CONSTRAINT ck_model_invocation_log_api_call_count_positive
        CHECK (api_call_count >= 1),
    CONSTRAINT ck_model_invocation_log_error_requires_message
        CHECK (status <> 'error' OR error_message IS NOT NULL)
) PARTITION BY RANGE (created_at);
COMMENT ON TABLE governance.model_invocation_log IS
    'tier:2 bulk-log append-only. One row per model API call. Range-partitioned by month on created_at; BRIN on created_at. decision_log_id/model_id are soft refs (Tier-2 decouple); no cascade — logs are never deleted.';

CREATE INDEX brin_model_invocation_log_created_at
    ON governance.model_invocation_log USING brin (created_at);
CREATE INDEX ix_model_invocation_log_decision
    ON governance.model_invocation_log (decision_log_id);
CREATE INDEX ix_model_invocation_log_model_started
    ON governance.model_invocation_log (model_id, started_at);

CREATE TABLE governance.model_invocation_log_2026_05
    PARTITION OF governance.model_invocation_log
    FOR VALUES FROM ('2026-05-01') TO ('2026-06-01');
CREATE TABLE governance.model_invocation_log_2026_06
    PARTITION OF governance.model_invocation_log
    FOR VALUES FROM ('2026-06-01') TO ('2026-07-01');


-- =============================================================================
-- TIER-1: PER-FIELD HITL OVERRIDE (append-only audit fact)
-- =============================================================================

-- governance.hitl_override — one immutable row per human override of one AI output
-- field. v1 runtime.hitl_override: KEEP (runtime -> governance, rehardened).
-- Tier-1 system-of-record (override audit facts are governance-material, read-often,
-- low-volume; per ADR-0004 override records live in Tier-1). Append-only.
-- decision_log_id is a SOFT ref (parent is Tier-2/partitioned); v1's ON DELETE
-- CASCADE is dropped — override audit rows are immutable and never cascade-deleted.
-- created_by hardened to a soft ref to governance.user (auth domain).
CREATE TABLE governance.hitl_override (
    hitl_override_id   uuid         NOT NULL DEFAULT governance.uuidv7(),
    decision_log_id    uuid         NOT NULL,            -- soft ref -> agent_decision_log (Tier-2)
    output_path        text         NOT NULL,            -- JSON path of the overridden field
    ai_value           jsonb,
    ai_found           boolean      NOT NULL,
    hitl_value         jsonb        NOT NULL,
    application        text         NOT NULL,
    business_entity_type text       NOT NULL,            -- v1 entity_type (free text business taxonomy, distinct from registry entity_type enum)
    entity_reference   text         NOT NULL,
    fact_type          text         NOT NULL,
    reason             text,
    created_by         uuid         NOT NULL,            -- soft ref -> governance.user (auth domain)
    created_at         timestamptz  NOT NULL DEFAULT now(),
    CONSTRAINT pk_hitl_override PRIMARY KEY (hitl_override_id)
);
COMMENT ON TABLE governance.hitl_override IS
    'tier:1 system-of-record, append-only. One immutable row per human override of one AI output field. decision_log_id is a soft ref to the Tier-2 decision log; no cascade.';
COMMENT ON COLUMN governance.hitl_override.business_entity_type IS
    'Free-text business taxonomy (v1 entity_type varchar) — intentionally NOT the registry governance.entity_type enum.';

CREATE INDEX ix_hitl_override_decision
    ON governance.hitl_override (decision_log_id);
CREATE INDEX ix_hitl_override_fact
    ON governance.hitl_override (application, business_entity_type, fact_type);
CREATE INDEX ix_hitl_override_entity_ref
    ON governance.hitl_override (application, business_entity_type, entity_reference);
CREATE INDEX ix_hitl_override_created_at
    ON governance.hitl_override (created_at);
CREATE INDEX ix_hitl_override_created_by
    ON governance.hitl_override (created_by);


-- =============================================================================
-- VIEW: point-in-time invocation cost (cost computed, never stored)
-- =============================================================================

-- governance.v_model_invocation_cost — v1 analytics.v_model_invocation_cost: KEEP.
-- Joins each invocation to the model_price row whose [valid_from, valid_to) window
-- contains started_at, and computes per-component + total cost on the fly.
CREATE VIEW governance.v_model_invocation_cost AS
SELECT
    mil.model_invocation_log_id,
    mil.decision_log_id,
    mil.model_id,
    mil.provider,
    mil.model_name,
    mil.started_at,
    mil.completed_at,
    mil.input_tokens,
    mil.output_tokens,
    mil.cache_creation_input_tokens,
    mil.cache_read_input_tokens,
    mp.currency,
    mp.input_price_per_1m,
    mp.output_price_per_1m,
    mp.cache_read_price_per_1m,
    mp.cache_write_price_per_1m,
    (mil.input_tokens  / 1000000.0) * mp.input_price_per_1m                              AS input_cost,
    (mil.output_tokens / 1000000.0) * mp.output_price_per_1m                             AS output_cost,
    (mil.cache_creation_input_tokens / 1000000.0) * COALESCE(mp.cache_write_price_per_1m, 0) AS cache_write_cost,
    (mil.cache_read_input_tokens     / 1000000.0) * COALESCE(mp.cache_read_price_per_1m, 0)  AS cache_read_cost,
      (mil.input_tokens  / 1000000.0) * mp.input_price_per_1m
    + (mil.output_tokens / 1000000.0) * mp.output_price_per_1m
    + (mil.cache_creation_input_tokens / 1000000.0) * COALESCE(mp.cache_write_price_per_1m, 0)
    + (mil.cache_read_input_tokens     / 1000000.0) * COALESCE(mp.cache_read_price_per_1m, 0) AS total_cost
FROM governance.model_invocation_log AS mil
LEFT JOIN governance.model_price AS mp
       ON mp.model_id = mil.model_id
      AND mil.started_at >= mp.valid_from
      AND (mp.valid_to IS NULL OR mil.started_at < mp.valid_to);
COMMENT ON VIEW governance.v_model_invocation_cost IS
    'Point-in-time cost per invocation: each call priced by the model_price row whose [valid_from, valid_to) window contains started_at. Cost is computed here, never persisted.';
