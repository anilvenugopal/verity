-- =====================================================================
-- 07-runs.sql — Verity v2 hardened schema · RUN/EXECUTION STATE, DISPATCH, QUOTAS
-- Event-sourced run state (runtime schema), the NATS transactional outbox, and
-- per-D-clarify configurable quotas. Re-applied per D1 (run_* native enums),
-- D3 (runtime state = core-tier; runtime schema), D4 (event-sourced + current view),
-- D6 (actor attribution), and the A/B run-mode clarification.
-- =====================================================================

-- runtime schema for execution state (Tier-1 transactional, read live)
CREATE SCHEMA IF NOT EXISTS runtime;

-- ===== native enums kept per D1 (hot-path dispatch/run state) =========
CREATE TYPE runtime.run_status            AS ENUM ('submitted', 'claimed', 'heartbeat', 'released');
CREATE TYPE runtime.run_completion_status AS ENUM ('complete', 'cancelled', 'errored');
CREATE TYPE runtime.run_entity_kind       AS ENUM ('agent', 'task');
CREATE TYPE runtime.outbox_status         AS ENUM ('pending', 'published', 'claimed', 'failed');

-- ===== execution_run (header) =========================================
CREATE TABLE runtime.execution_run (
    execution_run_id        uuid       NOT NULL DEFAULT uuidv7(),
    executable_version_id   uuid       NOT NULL,                 -- the version that ran (FK to core)
    run_entity_kind         runtime.run_entity_kind NOT NULL,
    application_id          uuid       NOT NULL,
    deployment_id           uuid,                                 -- soft -> core deployment (08)
    deployment_run_mode_code text,                                -- live|shadow|ab|locked (FK to reference in 08)
    ab_sample               text,                                 -- A/B sample scope marker (when run_mode=ab)
    run_purpose_code        text       NOT NULL DEFAULT 'production',
    business_context_key    text,                                 -- e.g. the ticker (links workflow steps)
    submitted_at            timestamptz NOT NULL DEFAULT now(),
    submitted_by_actor_id   uuid       NOT NULL,                 -- the AUTOMATION actor (harness) or human
    submitted_role_code     text       NOT NULL,
    CONSTRAINT pk_execution_run PRIMARY KEY (execution_run_id),
    CONSTRAINT fk_execution_run_version FOREIGN KEY (executable_version_id)
        REFERENCES core.executable_version (executable_version_id) ON DELETE RESTRICT,
    CONSTRAINT fk_execution_run_application FOREIGN KEY (application_id)
        REFERENCES core.application (application_id) ON DELETE RESTRICT,
    CONSTRAINT fk_execution_run_purpose FOREIGN KEY (run_purpose_code) REFERENCES reference.run_purpose (code),
    CONSTRAINT fk_execution_run_submitted_by FOREIGN KEY (submitted_by_actor_id) REFERENCES core.actor (actor_id),
    CONSTRAINT fk_execution_run_submitted_role FOREIGN KEY (submitted_role_code) REFERENCES reference.role (code));
COMMENT ON TABLE runtime.execution_run IS 'tier:1. A governed run of an executable_version. Carries deployment_run_mode + ab_sample (A/B tagging). State is event-sourced in execution_run_status. ADR-0002/PCR.';
CREATE INDEX ix_execution_run_version ON runtime.execution_run (executable_version_id);
CREATE INDEX ix_execution_run_context ON runtime.execution_run (business_context_key);

-- ===== execution_run_status (append-only state machine; D4) ===========
CREATE TABLE runtime.execution_run_status (
    execution_run_status_id uuid      NOT NULL DEFAULT uuidv7(),
    execution_run_id        uuid      NOT NULL,
    run_status              runtime.run_status NOT NULL,
    completion_status       runtime.run_completion_status,        -- set on the terminal 'released' event
    worker_instance_id      uuid,                                  -- soft -> harness_instance (08)
    decision_log_id         uuid,                                  -- soft -> audit.decision_log (terminal)
    error_code              text,
    detail                  jsonb      NOT NULL DEFAULT '{}'::jsonb,
    created_at              timestamptz NOT NULL DEFAULT now(),
    CONSTRAINT pk_execution_run_status PRIMARY KEY (execution_run_status_id),
    CONSTRAINT fk_execution_run_status_run FOREIGN KEY (execution_run_id)
        REFERENCES runtime.execution_run (execution_run_id) ON DELETE RESTRICT);
COMMENT ON TABLE runtime.execution_run_status IS 'tier:1 append-only. One row per run state transition (submitted/claimed/heartbeat/released). Current state via execution_run_current. Generalized v1 event-sourced model. D4.';
CREATE INDEX ix_execution_run_status_run_time ON runtime.execution_run_status (execution_run_id, created_at DESC);

CREATE VIEW runtime.execution_run_current AS
SELECT DISTINCT ON (execution_run_id)
       execution_run_id, run_status, completion_status, worker_instance_id, decision_log_id, error_code, created_at AS as_of
FROM   runtime.execution_run_status
ORDER  BY execution_run_id, created_at DESC;
COMMENT ON VIEW runtime.execution_run_current IS 'Current state per run (latest status event). The status path reads this view, never the analytics tier (PCR §3.4).';

-- ===== run_dispatch_outbox (transactional outbox; PCR §3.3) ===========
CREATE TABLE runtime.run_dispatch_outbox (
    run_dispatch_outbox_id uuid       NOT NULL DEFAULT uuidv7(),
    execution_run_id       uuid       NOT NULL,
    outbox_status          runtime.outbox_status NOT NULL DEFAULT 'pending',
    subject                text       NOT NULL,                   -- NATS subject (e.g. verity.runs.pending)
    payload                jsonb      NOT NULL,
    published_at           timestamptz,
    claimed_at             timestamptz,
    created_at             timestamptz NOT NULL DEFAULT now(),
    CONSTRAINT pk_run_dispatch_outbox PRIMARY KEY (run_dispatch_outbox_id),
    CONSTRAINT fk_run_dispatch_outbox_run FOREIGN KEY (execution_run_id)
        REFERENCES runtime.execution_run (execution_run_id) ON DELETE RESTRICT);
COMMENT ON TABLE runtime.run_dispatch_outbox IS 'tier:1. Transactional outbox: run insert + outbox row in one txn; verity-relay publishes to NATS and marks published_at (PCR §3.3).';
CREATE INDEX ix_run_dispatch_outbox_unpublished ON runtime.run_dispatch_outbox (created_at) WHERE outbox_status = 'pending';

-- ===== quotas (per-D-clarify configurable enforcement) ================
CREATE TABLE core.quota (
    quota_id              uuid       NOT NULL DEFAULT uuidv7(),
    quota_scope_type_code text       NOT NULL,                    -- application|agent|task|model
    scope_id              uuid       NOT NULL,                    -- soft polymorphic (validated at API per scope_type)
    quota_period_code     text       NOT NULL,
    budget                numeric(14,2) NOT NULL,
    currency_code         text       NOT NULL DEFAULT 'usd',
    enforcement_mode_code text       NOT NULL DEFAULT 'soft',     -- soft (default) | hard (D-clarify)
    warning_threshold_pct numeric(5,2) NOT NULL DEFAULT 80.00,
    enabled               boolean     NOT NULL DEFAULT true,
    notes                 text,
    created_at            timestamptz NOT NULL DEFAULT now(),
    updated_at            timestamptz NOT NULL DEFAULT now(),
    created_by_actor_id   uuid       NOT NULL,
    created_role_code     text       NOT NULL,
    CONSTRAINT pk_quota PRIMARY KEY (quota_id),
    CONSTRAINT fk_quota_scope_type FOREIGN KEY (quota_scope_type_code) REFERENCES reference.quota_scope_type (code),
    CONSTRAINT fk_quota_period FOREIGN KEY (quota_period_code) REFERENCES reference.quota_period (code),
    CONSTRAINT fk_quota_currency FOREIGN KEY (currency_code) REFERENCES reference.currency (code),
    CONSTRAINT fk_quota_enforcement FOREIGN KEY (enforcement_mode_code) REFERENCES reference.quota_enforcement_mode (code),
    CONSTRAINT fk_quota_created_by FOREIGN KEY (created_by_actor_id) REFERENCES core.actor (actor_id),
    CONSTRAINT fk_quota_created_role FOREIGN KEY (created_role_code) REFERENCES reference.role (code));
COMMENT ON TABLE core.quota IS 'tier:1. A budget quota over a scope/period. enforcement_mode soft (default; warn) or hard (refuse the run as an execution-phase control). D-clarify.';

CREATE TABLE core.quota_check (
    quota_check_id        uuid       NOT NULL DEFAULT uuidv7(),
    quota_id              uuid       NOT NULL,
    period_start          timestamptz NOT NULL,
    period_spend          numeric(14,2) NOT NULL,
    alert_level_code      text,                                   -- warning|exceeded|critical (NULL = ok)
    refused               boolean     NOT NULL DEFAULT false,     -- true only when hard enforcement refused a run
    execution_run_id      uuid,                                   -- soft -> the run that triggered the check
    created_at            timestamptz NOT NULL DEFAULT now(),
    CONSTRAINT pk_quota_check PRIMARY KEY (quota_check_id),
    CONSTRAINT fk_quota_check_quota FOREIGN KEY (quota_id) REFERENCES core.quota (quota_id) ON DELETE RESTRICT,
    CONSTRAINT fk_quota_check_alert FOREIGN KEY (alert_level_code) REFERENCES reference.quota_alert_level (code));
COMMENT ON TABLE core.quota_check IS 'tier:1 append-only. A quota evaluation (spend vs budget) with alert level; refused=true only under hard enforcement. Latest-per-quota = current breach state.';
CREATE INDEX ix_quota_check_quota_time ON core.quota_check (quota_id, created_at DESC);
