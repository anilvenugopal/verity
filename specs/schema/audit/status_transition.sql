-- audit.status_transition  ·  subject: decisions  ·  (table)

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
