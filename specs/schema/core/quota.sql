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
COMMENT ON TABLE core.quota IS 'tier:1. A budget quota over a scope/period. enforcement_mode soft (default; warn) or hard (refuse the run as an execution-phase control). D-clarify.';
