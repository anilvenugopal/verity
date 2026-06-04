-- core.quota  ·  subject: runs  ·  (table)

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
COMMENT ON TABLE core.quota IS
'A spending budget over a scope and period that the harness enforces at execution time. In
soft mode a breach only warns (and is logged as a quota_check); in hard mode it refuses the
run outright — the single switch that turns cost observability into a real execution-phase
control. The coordinator caches the active quota so it keeps enforcing during island mode
(ADR-0010).

@tier 1
@lifecycle mutable
@subject runs
@status reference.quota_enforcement_mode
@invariant hard mode refuses the run; soft mode only warns';
COMMENT ON COLUMN core.quota.quota_id IS 'Identity of the budget.';
COMMENT ON COLUMN core.quota.quota_scope_type_code IS
'What the budget applies to — application, agent, task, or model — which determines how scope_id is interpreted. @status reference.quota_scope_type';
COMMENT ON COLUMN core.quota.scope_id IS
'The id of the scoped thing; polymorphic and validated against scope_type at the API, since no single FK can express the four possible targets.';
COMMENT ON COLUMN core.quota.quota_period_code IS
'The window the budget resets over (e.g. daily, monthly). @status reference.quota_period';
COMMENT ON COLUMN core.quota.budget IS
'The spend ceiling for one period, denominated in currency_code. @units currency';
COMMENT ON COLUMN core.quota.currency_code IS
'Currency of the budget and of the spend it is compared against. @status reference.currency';
COMMENT ON COLUMN core.quota.enforcement_mode_code IS
'soft = warn and continue; hard = refuse the run. The boundary between observability and enforcement. @status reference.quota_enforcement_mode';
COMMENT ON COLUMN core.quota.warning_threshold_pct IS
'Percent of budget at which a warning quota_check fires before the ceiling is reached. @units percent';
COMMENT ON COLUMN core.quota.enabled IS
'Whether this quota is currently in force; disabling stops enforcement without deleting the budget or its history.';
COMMENT ON COLUMN core.quota.notes IS 'Free-text rationale for the budget.';
COMMENT ON COLUMN core.quota.created_at IS 'When the quota was created.';
COMMENT ON COLUMN core.quota.updated_at IS 'When the quota was last adjusted.';
COMMENT ON COLUMN core.quota.created_by_actor_id IS 'Who set the budget. @ref core.actor hard';
COMMENT ON COLUMN core.quota.created_role_code IS 'The capacity they acted in (D6). @status reference.role';
