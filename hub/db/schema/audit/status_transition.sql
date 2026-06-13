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
COMMENT ON TABLE audit.status_transition IS
'The ONE shared transition log for every mutable *_status_code in the schema (intake, requirement, plan, approval, exception, ROI/cost lock, deployment, …). Instead of a per-table history, a single append-only stream records from_code -> to_code with attribution; entity_type + entity_id are soft refs to the core row that changed (D4).

@tier 2
@lifecycle append-only
@subject decisions
@partitioned RANGE(created_at)
@decision D4';
CREATE INDEX ix_status_transition_entity ON audit.status_transition (entity_type, entity_id, created_at DESC);
CREATE TABLE audit.status_transition_2026_06 PARTITION OF audit.status_transition FOR VALUES FROM ('2026-06-01') TO ('2026-07-01');
CREATE TABLE audit.status_transition_2026_07 PARTITION OF audit.status_transition FOR VALUES FROM ('2026-07-01') TO ('2026-08-01');
COMMENT ON COLUMN audit.status_transition.status_transition_id IS
'Identity of the transition (with created_at, the partition key).';
COMMENT ON COLUMN audit.status_transition.entity_type IS
'Which kind of row changed — intake/approval_request/compliance_exception/… — which interprets entity_id.';
COMMENT ON COLUMN audit.status_transition.entity_id IS
'The core row whose status changed; soft ref, polymorphic by entity_type.';
COMMENT ON COLUMN audit.status_transition.status_field IS
'Which coded field changed (e.g. intake_status_code), for rows with more than one status.';
COMMENT ON COLUMN audit.status_transition.from_code IS
'Prior code; null on the first transition.';
COMMENT ON COLUMN audit.status_transition.to_code IS
'New code after the transition.';
COMMENT ON COLUMN audit.status_transition.actor_id IS
'Who made the change. @ref core.actor soft';
COMMENT ON COLUMN audit.status_transition.acting_role_code IS
'The capacity they acted in. @status reference.role';
COMMENT ON COLUMN audit.status_transition.reason IS
'Why the status changed.';
COMMENT ON COLUMN audit.status_transition.created_at IS
'When the transition occurred; the partition key.';
