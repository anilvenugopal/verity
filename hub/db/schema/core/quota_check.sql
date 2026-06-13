-- core.quota_check  ·  subject: runs  ·  (table)

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
COMMENT ON TABLE core.quota_check IS
'An append-only record of one quota evaluation: spend-so-far versus budget for the period, the alert level it crossed, and whether a hard quota refused the triggering run. The latest row per quota is that quota''s current breach state; the coordinator writes these as it enforces, including from its cached quota during island mode (ADR-0010).

@tier 1
@lifecycle append-only
@subject runs
@status reference.quota_alert_level';
CREATE INDEX ix_quota_check_quota_time ON core.quota_check (quota_id, created_at DESC);
COMMENT ON COLUMN core.quota_check.quota_check_id IS
'Identity of this evaluation.';
COMMENT ON COLUMN core.quota_check.quota_id IS
'The budget being evaluated. @ref core.quota hard';
COMMENT ON COLUMN core.quota_check.period_start IS
'Start of the period this evaluation covers; spend is summed from here forward.';
COMMENT ON COLUMN core.quota_check.period_spend IS
'Cumulative spend in the period at evaluation time, compared against the quota budget. @units currency';
COMMENT ON COLUMN core.quota_check.alert_level_code IS
'warning/exceeded/critical, or null when within budget — the escalation signal surfaced to portals and alerts. @status reference.quota_alert_level';
COMMENT ON COLUMN core.quota_check.refused IS
'True only when a hard quota actually refused the triggering run; distinguishes an enforced denial from a mere warning.';
COMMENT ON COLUMN core.quota_check.execution_run_id IS
'The run whose submission triggered this check. @ref core.execution_run soft';
COMMENT ON COLUMN core.quota_check.created_at IS
'When the evaluation ran; latest-per-quota gives the current state.';
