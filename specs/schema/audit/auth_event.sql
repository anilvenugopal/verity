-- audit.auth_event  ·  subject: decisions  ·  (table)

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
