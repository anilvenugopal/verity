-- audit.evidence  ·  subject: decisions  ·  (table)

CREATE TABLE audit.evidence (
    evidence_id            uuid       NOT NULL DEFAULT uuidv7(),
    canonical_requirement_id uuid,                               -- soft refs -> compliance (core), pinned versions
    requirement_tier_id    uuid,
    control_id             uuid,
    evidence_specification_id uuid,
    control_phase_code     text,                                 -- design_time|deploy_time|static_model|execution
    evidence_artifact_type_code text,
    executable_version_id  uuid,                                 -- what produced it (soft)
    run_id                 uuid,                                 -- soft -> execution_run
    decision_log_id        uuid,                                 -- soft -> decision_log
    storage_ref            jsonb,                                -- where the artifact lives (connector + locator + digest)
    produced_by_actor_id   uuid       NOT NULL,                  -- AUTOMATION (auto-captured) or human (attested) — D6
    produced_role_code     text       NOT NULL,
    created_at             timestamptz NOT NULL DEFAULT now(),
    CONSTRAINT pk_evidence PRIMARY KEY (evidence_id, created_at)
) PARTITION BY RANGE (created_at);
COMMENT ON TABLE audit.evidence IS 'tier:2 append-only (partitioned). The compliance evidence FACT stream (vs evidence_specification = the spec). Tied to requirement+tier+phase+entity/run. produced_by an actor (automation for auto-captured). ADR-0008.';
CREATE INDEX ix_evidence_requirement_time ON audit.evidence (canonical_requirement_id, created_at DESC);
CREATE INDEX brin_evidence_time ON audit.evidence USING brin (created_at);
CREATE TABLE audit.evidence_2026_06 PARTITION OF audit.evidence FOR VALUES FROM ('2026-06-01') TO ('2026-07-01');
CREATE TABLE audit.evidence_2026_07 PARTITION OF audit.evidence FOR VALUES FROM ('2026-07-01') TO ('2026-08-01');
