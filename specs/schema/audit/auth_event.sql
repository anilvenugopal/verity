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
COMMENT ON TABLE audit.auth_event IS
'Authentication and authorization events — logins, logouts, session expiry/termination, and authorization denials — for the security audit trail. Tier-2, partitioned. actor_id is nullable because pre-identity failures (e.g. a bad signature) have no resolved actor (FR-024).

@tier 2
@lifecycle append-only
@subject decisions
@partitioned RANGE(created_at)
@enum audit.auth_event_type
@see user-authentication';
CREATE INDEX ix_auth_event_actor_time ON audit.auth_event (actor_id, created_at DESC);
CREATE TABLE audit.auth_event_2026_06 PARTITION OF audit.auth_event FOR VALUES FROM ('2026-06-01') TO ('2026-07-01');
CREATE TABLE audit.auth_event_2026_07 PARTITION OF audit.auth_event FOR VALUES FROM ('2026-07-01') TO ('2026-08-01');
COMMENT ON COLUMN audit.auth_event.auth_event_id IS
'Identity of the event (with created_at, the partition key).';
COMMENT ON COLUMN audit.auth_event.event_type IS
'login/logout/session_expiry/session_termination/authz_denial. @enum audit.auth_event_type';
COMMENT ON COLUMN audit.auth_event.outcome IS
'success/failure/denied. @enum audit.auth_event_outcome';
COMMENT ON COLUMN audit.auth_event.reason_code IS
'Why it failed or was denied — bad_signature/expired/nonce_mismatch/unknown_tenant/mock_auth/…';
COMMENT ON COLUMN audit.auth_event.actor_id IS
'The actor, when known; null for pre-identity failures. @ref core.actor soft';
COMMENT ON COLUMN audit.auth_event.action_code IS
'The action attempted (for an authorization denial).';
COMMENT ON COLUMN audit.auth_event.resource IS
'The resource the action targeted.';
COMMENT ON COLUMN audit.auth_event.request_id IS
'Correlation id of the request.';
COMMENT ON COLUMN audit.auth_event.ip IS
'Source IP address.';
COMMENT ON COLUMN audit.auth_event.created_at IS
'When the event occurred; the partition key.';
