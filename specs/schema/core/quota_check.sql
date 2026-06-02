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
COMMENT ON TABLE core.quota_check IS 'tier:1 append-only. A quota evaluation (spend vs budget) with alert level; refused=true only under hard enforcement. Latest-per-quota = current breach state.';
CREATE INDEX ix_quota_check_quota_time ON core.quota_check (quota_id, created_at DESC);
