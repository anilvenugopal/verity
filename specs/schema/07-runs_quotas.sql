-- 07-runs_quotas.sql — hardened v2 schema domain: runs_quotas
-- See ASSEMBLY-AND-VERIFICATION.md for cross-domain FKs & review items.

-- =============================================================================
-- DOMAIN: RUN / EXECUTION STATE + QUOTAS + DISPATCH
-- Schema: runtime (run state machine + dispatch), governance (quotas)
-- Hardening: ADR-0005 (naming/structure/insert-only/tiering), ADR-0004 (tiering),
--            PCR section 3.3 (transactional outbox).
--
-- KEY GENERATOR: uuidv7() (PG18+, time-ordered for index/BRIN locality, replica-mintable).
--   FALLBACK (PG<18): create a uuidv7() SQL wrapper over gen_random_uuid(), or use the
--   pg_uuidv7 extension. v1 used uuid_generate_v4() (uuid-ossp) — retired in v2.
--   Example fallback shim (apply once if server < PG18):
--     -- CREATE FUNCTION public.uuidv7() RETURNS uuid LANGUAGE sql VOLATILE AS
--     -- $$ SELECT gen_random_uuid() $$;  -- NON-time-ordered fallback; replace on PG18+.
--
-- TIERING: every table in this domain is Tier-1 (system-of-record run STATE + quotas +
--   dispatch), per ADR-0004 ("transactional run state ... stays small and relational").
--   The high-volume Tier-2 bulk logs (agent_decision_log, model_invocation_log,
--   runtime_event) belong to the DECISION-LOG/ANALYTICS domain and are NOT defined here;
--   this domain only FK-references agent_decision_log for terminal drill-through.
-- =============================================================================

-- -----------------------------------------------------------------------------
-- ENUM TYPES
-- -----------------------------------------------------------------------------

-- Run state-machine transition kinds (append-only event vocabulary).
-- Generalizes v1 runtime.execution_run_status.status CHECK ('submitted','claimed',
-- 'heartbeat','released') into a named enum per naming-conventions §9.
CREATE TYPE runtime.run_status AS ENUM (
    'submitted',
    'claimed',
    'heartbeat',
    'released'
);
COMMENT ON TYPE runtime.run_status IS
    'Run state-machine transition kinds recorded append-only on runtime.execution_run_status. Terminal outcomes (complete/cancelled/failed) live in the completion/error tables, not here.';

-- Terminal completion outcome (non-error). v1 used VARCHAR CHECK ('complete','cancelled').
CREATE TYPE runtime.run_completion_status AS ENUM (
    'complete',
    'cancelled'
);
COMMENT ON TYPE runtime.run_completion_status IS
    'Non-error terminal outcome for a run; recorded once per run on runtime.execution_run_completion.';

-- Entity kind a run targets. v1 used VARCHAR CHECK ('task','agent') on execution_run.
CREATE TYPE runtime.run_entity_kind AS ENUM (
    'task',
    'agent'
);
COMMENT ON TYPE runtime.run_entity_kind IS 'Whether a run targets a task version or an agent version.';

-- Write/side-effect mode for a run. v1 had free-text execution_run.write_mode + the
-- lifecycle-gated "read-only" concept from PCR 3.7 (Target Bindings suppressed).
CREATE TYPE runtime.run_write_mode AS ENUM (
    'live',
    'read_only'
);
COMMENT ON TYPE runtime.run_write_mode IS
    'live = Target Bindings execute (business side effects); read_only = harness runs and logs but Target Bindings are suppressed (PCR 3.7 shadow/challenger/deprecated environments).';

-- Quota scope target. v1 used VARCHAR CHECK ('application','agent','task','model').
CREATE TYPE governance.quota_scope_type AS ENUM (
    'application',
    'agent',
    'task',
    'model'
);
COMMENT ON TYPE governance.quota_scope_type IS 'What a spend quota is scoped to.';

-- Quota budgeting period. v1 used VARCHAR CHECK ('daily','weekly','monthly').
CREATE TYPE governance.quota_period AS ENUM (
    'daily',
    'weekly',
    'monthly'
);
COMMENT ON TYPE governance.quota_period IS 'Rolling budget window for a quota.';

-- V2-NEW: configurable enforcement action when a quota is exceeded. Replaces v1's
-- single boolean hard_stop with a richer, configurable enforcement vocabulary while
-- preserving the hard_stop semantic verbatim (hard_stop == enforcement_action 'block').
CREATE TYPE governance.quota_enforcement_action AS ENUM (
    'alert_only',   -- fire alert, never block (== v1 hard_stop = false)
    'block',        -- refuse new runs once budget exceeded (== v1 hard_stop = true)
    'throttle'      -- admit at reduced concurrency once budget exceeded (v2-new option)
);
COMMENT ON TYPE governance.quota_enforcement_action IS
    'Configurable action when a quota period budget is exceeded. v1 boolean hard_stop maps to block (true) / alert_only (false); throttle is v2-new.';

-- Alert severity recorded on a quota_check. v1 used free-text VARCHAR alert_level.
CREATE TYPE governance.quota_alert_level AS ENUM (
    'warning',      -- crossed alert_threshold_pct
    'exceeded',     -- crossed 100% of budget
    'critical'      -- crossed a hard escalation band
);
COMMENT ON TYPE governance.quota_alert_level IS 'Severity band of a fired quota alert.';

-- V2-NEW: lifecycle of a transactional outbox row (PCR section 3.3).
CREATE TYPE runtime.outbox_status AS ENUM (
    'pending',      -- inserted in the run-submit txn, not yet published to NATS
    'published',    -- relay published to NATS, awaiting claim
    'claimed',      -- a worker claimed the run
    'failed'        -- relay/publish failed terminally (parked for sweep/ops)
);
COMMENT ON TYPE runtime.outbox_status IS
    'Transactional-outbox row lifecycle for run dispatch (PCR 3.3): pending -> published -> claimed; failed is a terminal park state.';

-- =============================================================================
-- TIER-1: RUN STATE MACHINE (event-sourced, append-only)
-- =============================================================================

-- -----------------------------------------------------------------------------
-- runtime.execution_run  (Tier-1, append-only submission record)
--   One immutable row per submitted run. State is NOT stored here; it is projected
--   from the append-only status/completion/error event tables via execution_run_current.
-- -----------------------------------------------------------------------------
CREATE TABLE runtime.execution_run (
    execution_run_id        uuid                    NOT NULL DEFAULT uuidv7(),
    entity_kind             runtime.run_entity_kind NOT NULL,
    entity_version_id       uuid                    NOT NULL,
    entity_name             text                    NOT NULL,
    channel                 governance.deployment_channel NOT NULL,
    application              text                    NOT NULL DEFAULT 'default',
    input_json              jsonb,
    execution_context_id    uuid,
    workflow_run_id         uuid,                   -- soft pointer (app-maintained), no FK
    parent_decision_id      uuid,                   -- soft pointer to agent_decision_log, no FK
    mock_mode               boolean                 NOT NULL DEFAULT false,
    write_mode              runtime.run_write_mode  NOT NULL DEFAULT 'live',
    enforce_output_schema   boolean                 NOT NULL DEFAULT true,
    submitted_at            timestamptz             NOT NULL DEFAULT now(),
    submitted_by            text,
    CONSTRAINT pk_execution_run PRIMARY KEY (execution_run_id),
    CONSTRAINT fk_execution_run_context
        FOREIGN KEY (execution_context_id)
        REFERENCES runtime.execution_context (execution_context_id)
        ON DELETE RESTRICT
);
COMMENT ON TABLE runtime.execution_run IS
    'tier:1 append-only. Immutable submission record for one run. Current state is the execution_run_current view over the append-only status/completion/error event tables (ADR-0004/0005 insert-only model).';
COMMENT ON COLUMN runtime.execution_run.workflow_run_id IS 'Soft pointer (app-maintained), intentionally no DB FK — correlates runs in a multi-step workflow.';
COMMENT ON COLUMN runtime.execution_run.parent_decision_id IS 'Soft pointer to runtime.agent_decision_log (Tier-2 decision-log domain), intentionally no DB FK to avoid cross-tier coupling.';
COMMENT ON COLUMN runtime.execution_run.write_mode IS 'live vs read_only (Target Bindings suppressed); read_only is the PCR 3.7 shadow/challenger/deprecated execution mode.';

CREATE INDEX ix_execution_run_entity
    ON runtime.execution_run (entity_kind, entity_version_id);
CREATE INDEX ix_execution_run_context_id
    ON runtime.execution_run (execution_context_id);
CREATE INDEX ix_execution_run_workflow_id
    ON runtime.execution_run (workflow_run_id);
CREATE INDEX ix_execution_run_submitted_at
    ON runtime.execution_run (submitted_at DESC);
CREATE INDEX ix_execution_run_application
    ON runtime.execution_run (application);

-- -----------------------------------------------------------------------------
-- runtime.execution_run_status  (Tier-1, append-only event table)
--   One immutable row per non-terminal state transition (submitted/claimed/heartbeat/
--   released). Never updated. The state-machine history IS this table.
-- -----------------------------------------------------------------------------
CREATE TABLE runtime.execution_run_status (
    execution_run_status_id uuid                NOT NULL DEFAULT uuidv7(),
    execution_run_id        uuid                NOT NULL,
    status                  runtime.run_status  NOT NULL,
    worker_id               text,
    detail                  jsonb,
    created_at              timestamptz         NOT NULL DEFAULT now(),
    CONSTRAINT pk_execution_run_status PRIMARY KEY (execution_run_status_id),
    CONSTRAINT fk_execution_run_status_run
        FOREIGN KEY (execution_run_id)
        REFERENCES runtime.execution_run (execution_run_id)
        ON DELETE RESTRICT,
    CONSTRAINT ck_execution_run_status_worker_when_claimed
        CHECK (status <> 'claimed' OR worker_id IS NOT NULL)
);
COMMENT ON TABLE runtime.execution_run_status IS
    'tier:1 append-only event table. One row per run state transition (submitted/claimed/heartbeat/released). Immutable: no UPDATE/DELETE; advancing a run INSERTs a new row.';

CREATE INDEX ix_execution_run_status_run_id
    ON runtime.execution_run_status (execution_run_id, created_at DESC);

-- -----------------------------------------------------------------------------
-- runtime.execution_run_completion  (Tier-1, append-only terminal fact, one per run)
-- -----------------------------------------------------------------------------
CREATE TABLE runtime.execution_run_completion (
    execution_run_completion_id uuid                        NOT NULL DEFAULT uuidv7(),
    execution_run_id            uuid                        NOT NULL,
    final_status                runtime.run_completion_status NOT NULL,
    decision_log_id             uuid,
    duration_ms                 integer,
    worker_id                   text,
    completed_at                timestamptz                 NOT NULL DEFAULT now(),
    CONSTRAINT pk_execution_run_completion PRIMARY KEY (execution_run_completion_id),
    CONSTRAINT uq_execution_run_completion_run UNIQUE (execution_run_id),
    CONSTRAINT fk_execution_run_completion_run
        FOREIGN KEY (execution_run_id)
        REFERENCES runtime.execution_run (execution_run_id)
        ON DELETE RESTRICT,
    CONSTRAINT fk_execution_run_completion_decision
        FOREIGN KEY (decision_log_id)
        REFERENCES runtime.agent_decision_log (agent_decision_log_id)
        ON DELETE RESTRICT,
    CONSTRAINT ck_execution_run_completion_duration_nonneg
        CHECK (duration_ms IS NULL OR duration_ms >= 0)
);
COMMENT ON TABLE runtime.execution_run_completion IS
    'tier:1 append-only terminal fact: non-error completion of a run, at most one per run (uq_execution_run_completion_run). Immutable.';
COMMENT ON COLUMN runtime.execution_run_completion.decision_log_id IS 'FK to runtime.agent_decision_log (Tier-2 decision-log domain); drill-through to the terminal decision record.';

CREATE INDEX ix_execution_run_completion_decision_id
    ON runtime.execution_run_completion (decision_log_id);

-- -----------------------------------------------------------------------------
-- runtime.execution_run_error  (Tier-1, append-only terminal fact, one per run)
-- -----------------------------------------------------------------------------
CREATE TABLE runtime.execution_run_error (
    execution_run_error_id  uuid        NOT NULL DEFAULT uuidv7(),
    execution_run_id        uuid        NOT NULL,
    error_code              text,
    error_message           text        NOT NULL,
    error_trace             text,
    decision_log_id         uuid,
    worker_id               text,
    failed_at               timestamptz NOT NULL DEFAULT now(),
    CONSTRAINT pk_execution_run_error PRIMARY KEY (execution_run_error_id),
    CONSTRAINT uq_execution_run_error_run UNIQUE (execution_run_id),
    CONSTRAINT fk_execution_run_error_run
        FOREIGN KEY (execution_run_id)
        REFERENCES runtime.execution_run (execution_run_id)
        ON DELETE RESTRICT,
    CONSTRAINT fk_execution_run_error_decision
        FOREIGN KEY (decision_log_id)
        REFERENCES runtime.agent_decision_log (agent_decision_log_id)
        ON DELETE RESTRICT
);
COMMENT ON TABLE runtime.execution_run_error IS
    'tier:1 append-only terminal fact: error termination of a run, at most one per run (uq_execution_run_error_run). Immutable. Written before any data side effects on INTEGRITY_VIOLATION (PCR 3.2).';

CREATE INDEX ix_execution_run_error_decision_id
    ON runtime.execution_run_error (decision_log_id);

-- -----------------------------------------------------------------------------
-- runtime.execution_run_current  (current-state VIEW; never materialized in Tier-1)
--   Resolves current_status by precedence: completion.final_status -> 'failed' if an
--   error row exists -> latest status event -> 'submitted'. Exposes the PCR 3.6
--   run-detail columns: current_status, submitted_at, first_started_at,
--   current_worker_id, duration_ms.
-- -----------------------------------------------------------------------------
CREATE VIEW runtime.execution_run_current AS
SELECT
    r.execution_run_id,
    r.entity_kind,
    r.entity_version_id,
    r.entity_name,
    r.channel,
    r.application,
    r.write_mode,
    r.mock_mode,
    r.submitted_at,
    r.submitted_by,
    CASE
        WHEN comp.execution_run_id IS NOT NULL THEN comp.final_status::text
        WHEN err.execution_run_id  IS NOT NULL THEN 'failed'
        WHEN st.status             IS NOT NULL THEN st.status::text
        ELSE 'submitted'
    END                                                   AS current_status,
    claim.first_started_at,
    COALESCE(comp.worker_id, err.worker_id, st.worker_id) AS current_worker_id,
    COALESCE(
        comp.duration_ms,
        CASE
            WHEN comp.completed_at IS NOT NULL
                THEN (EXTRACT(EPOCH FROM (comp.completed_at - r.submitted_at)) * 1000)::integer
            WHEN err.failed_at IS NOT NULL
                THEN (EXTRACT(EPOCH FROM (err.failed_at - r.submitted_at)) * 1000)::integer
        END
    )                                                     AS duration_ms,
    comp.completed_at,
    comp.decision_log_id                                  AS completion_decision_log_id,
    err.failed_at,
    err.error_code,
    err.error_message,
    err.decision_log_id                                   AS error_decision_log_id
FROM runtime.execution_run AS r
LEFT JOIN runtime.execution_run_completion AS comp
    ON comp.execution_run_id = r.execution_run_id
LEFT JOIN runtime.execution_run_error AS err
    ON err.execution_run_id = r.execution_run_id
LEFT JOIN LATERAL (
    SELECT s.status, s.worker_id
    FROM runtime.execution_run_status AS s
    WHERE s.execution_run_id = r.execution_run_id
    ORDER BY s.created_at DESC, s.execution_run_status_id DESC
    LIMIT 1
) AS st ON true
LEFT JOIN LATERAL (
    SELECT min(s.created_at) AS first_started_at
    FROM runtime.execution_run_status AS s
    WHERE s.execution_run_id = r.execution_run_id
      AND s.status = 'claimed'
) AS claim ON true;
COMMENT ON VIEW runtime.execution_run_current IS
    'Current-state projection over the append-only run event tables. current_status precedence: completion -> error(=failed) -> latest status event -> submitted. Exposes PCR 3.6 run-detail columns.';

-- =============================================================================
-- V2-NEW: TIER-1 TRANSACTIONAL OUTBOX FOR RUN DISPATCH (PCR section 3.3)
-- =============================================================================

-- -----------------------------------------------------------------------------
-- runtime.run_dispatch_outbox
--   Inserted in the SAME transaction as execution_run on run submit. verity-relay
--   reads pending rows with SKIP LOCKED, publishes to NATS (verity.runs.pending),
--   and marks published_at. verity-dispatch-sweep re-publishes rows published but
--   not claimed within the timeout. Append-then-update-status (not insert-only):
--   this is dispatch plumbing, NOT an audit fact, so a small bounded mutable status
--   is acceptable and intentional. The audit record of the run is execution_run +
--   the append-only status events.
-- -----------------------------------------------------------------------------
CREATE TABLE runtime.run_dispatch_outbox (
    run_dispatch_outbox_id  uuid                    NOT NULL DEFAULT uuidv7(),
    execution_run_id        uuid                    NOT NULL,
    subject                 text                    NOT NULL DEFAULT 'verity.runs.pending',
    payload                 jsonb                   NOT NULL,
    status                  runtime.outbox_status   NOT NULL DEFAULT 'pending',
    publish_attempts        integer                 NOT NULL DEFAULT 0,
    last_error              text,
    created_at              timestamptz             NOT NULL DEFAULT now(),
    published_at            timestamptz,
    claimed_at              timestamptz,
    CONSTRAINT pk_run_dispatch_outbox PRIMARY KEY (run_dispatch_outbox_id),
    CONSTRAINT uq_run_dispatch_outbox_run UNIQUE (execution_run_id),
    CONSTRAINT fk_run_dispatch_outbox_run
        FOREIGN KEY (execution_run_id)
        REFERENCES runtime.execution_run (execution_run_id)
        ON DELETE RESTRICT,
    CONSTRAINT ck_run_dispatch_outbox_attempts_nonneg
        CHECK (publish_attempts >= 0),
    CONSTRAINT ck_run_dispatch_outbox_published_state
        CHECK (status <> 'published' OR published_at IS NOT NULL),
    CONSTRAINT ck_run_dispatch_outbox_claimed_state
        CHECK (status <> 'claimed' OR claimed_at IS NOT NULL)
);
COMMENT ON TABLE runtime.run_dispatch_outbox IS
    'tier:1 transactional outbox for run dispatch (PCR 3.3). One row per run, inserted in the same txn as execution_run. Relay publishes pending rows (SKIP LOCKED) to NATS and advances status; sweep re-publishes stuck rows. Dispatch plumbing, not an audit fact.';
COMMENT ON COLUMN runtime.run_dispatch_outbox.status IS 'pending -> published -> claimed; failed parks the row for ops. Bounded status mutation is intentional (dispatch state, not audit).';

-- Partial index over the relay hot path (pending rows oldest-first, for FOR UPDATE SKIP LOCKED).
CREATE INDEX ix_run_dispatch_outbox_pending
    ON runtime.run_dispatch_outbox (created_at)
    WHERE status = 'pending';
-- Partial index over the sweep path (published-but-not-yet-claimed rows).
CREATE INDEX ix_run_dispatch_outbox_published_unclaimed
    ON runtime.run_dispatch_outbox (published_at)
    WHERE status = 'published';

-- =============================================================================
-- TIER-1: QUOTAS + QUOTA CHECK
-- =============================================================================

-- -----------------------------------------------------------------------------
-- governance.quota  (Tier-1 system-of-record; configurable spend cap)
--   V2 delta: keeps the v1 boolean hard_stop AND adds the configurable
--   enforcement_action enum. hard_stop is retained as a generated mirror so existing
--   semantics/queries survive (hard_stop == enforcement_action = 'block').
-- -----------------------------------------------------------------------------
CREATE TABLE governance.quota (
    quota_id            uuid                            NOT NULL DEFAULT uuidv7(),
    scope_type          governance.quota_scope_type     NOT NULL,
    scope_id            uuid,                           -- polymorphic soft pointer (app-validated), no FK
    scope_name          text                            NOT NULL,
    period              governance.quota_period         NOT NULL,
    budget_usd          numeric(14,4)                   NOT NULL,
    alert_threshold_pct integer                         NOT NULL DEFAULT 80,
    enforcement_action  governance.quota_enforcement_action NOT NULL DEFAULT 'alert_only',
    hard_stop           boolean GENERATED ALWAYS AS (enforcement_action = 'block') STORED,
    enabled             boolean                         NOT NULL DEFAULT true,
    notes               text,
    created_at          timestamptz                     NOT NULL DEFAULT now(),
    updated_at          timestamptz                     NOT NULL DEFAULT now(),
    CONSTRAINT pk_quota PRIMARY KEY (quota_id),
    CONSTRAINT ck_quota_budget_positive
        CHECK (budget_usd > 0),
    CONSTRAINT ck_quota_alert_threshold_range
        CHECK (alert_threshold_pct BETWEEN 1 AND 200)
);
COMMENT ON TABLE governance.quota IS
    'tier:1 system-of-record. Spend budget for a scope/period with configurable enforcement_action. hard_stop is a generated mirror of enforcement_action=block (v1 compatibility).';
COMMENT ON COLUMN governance.quota.scope_id IS 'Polymorphic target id (application/agent/task/model), validated in the app layer; intentionally no DB FK (heterogeneous targets).';
COMMENT ON COLUMN governance.quota.hard_stop IS 'V1-compat generated column: TRUE iff enforcement_action = block. Configure via enforcement_action.';

CREATE INDEX ix_quota_scope
    ON governance.quota (scope_type, scope_id);
CREATE INDEX ix_quota_enabled
    ON governance.quota (enabled);

-- -----------------------------------------------------------------------------
-- governance.quota_check  (Tier-1, append-only evaluation record)
--   One immutable row per evaluation of a quota against a period's spend.
--   resolved_at flips an alert closed -> intentional bounded operational mutation,
--   not an audit edit (the evaluation facts spend_usd/spend_pct/alert_fired are
--   immutable once written).
-- -----------------------------------------------------------------------------
CREATE TABLE governance.quota_check (
    quota_check_id  uuid                            NOT NULL DEFAULT uuidv7(),
    quota_id        uuid                            NOT NULL,
    period_start    timestamptz                     NOT NULL,
    period_end      timestamptz                     NOT NULL,
    spend_usd       numeric(14,4)                   NOT NULL,
    budget_usd      numeric(14,4)                   NOT NULL,
    spend_pct       integer                         NOT NULL,
    alert_fired     boolean                         NOT NULL DEFAULT false,
    alert_level     governance.quota_alert_level,
    note            text,
    checked_at      timestamptz                     NOT NULL DEFAULT now(),
    resolved_at     timestamptz,
    CONSTRAINT pk_quota_check PRIMARY KEY (quota_check_id),
    CONSTRAINT fk_quota_check_quota
        FOREIGN KEY (quota_id)
        REFERENCES governance.quota (quota_id)
        ON DELETE CASCADE,
    CONSTRAINT ck_quota_check_period_order
        CHECK (period_end >= period_start),
    CONSTRAINT ck_quota_check_spend_nonneg
        CHECK (spend_usd >= 0 AND budget_usd >= 0 AND spend_pct >= 0),
    CONSTRAINT ck_quota_check_alert_level_when_fired
        CHECK (alert_fired = false OR alert_level IS NOT NULL)
);
COMMENT ON TABLE governance.quota_check IS
    'tier:1 append-only. One immutable evaluation of a quota vs period spend. Evaluation facts are never edited; resolved_at is a bounded operational close of an alert. CASCADE-deleted with its quota.';

CREATE INDEX ix_quota_check_quota_checked
    ON governance.quota_check (quota_id, checked_at DESC);
CREATE INDEX ix_quota_check_active
    ON governance.quota_check (alert_fired, resolved_at);
