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
COMMENT ON TABLE audit.evidence IS
'The compliance evidence FACT stream — the actual artifacts produced to satisfy controls, as opposed to evidence_specification (the spec). Each fact is tied to the pinned requirement/tier/phase and to what produced it (entity/run/decision), with a storage_ref to where the artifact lives. Tier-2, partitioned, soft refs to core; produced by an actor — automation for auto-captured, a human for attested (ADR-0008).

@tier 2
@lifecycle append-only
@subject decisions
@partitioned RANGE(created_at)
@status reference.control_phase
@status reference.evidence_artifact_type
@adr 0008';
CREATE INDEX ix_evidence_requirement_time ON audit.evidence (canonical_requirement_id, created_at DESC);
CREATE INDEX brin_evidence_time ON audit.evidence USING brin (created_at);
CREATE TABLE audit.evidence_2026_06 PARTITION OF audit.evidence FOR VALUES FROM ('2026-06-01') TO ('2026-07-01');
CREATE TABLE audit.evidence_2026_07 PARTITION OF audit.evidence FOR VALUES FROM ('2026-07-01') TO ('2026-08-01');
COMMENT ON COLUMN audit.evidence.evidence_id IS
'Identity of the evidence fact (with created_at, the partition key).';
COMMENT ON COLUMN audit.evidence.canonical_requirement_id IS
'The pinned requirement version the evidence supports. @ref core.canonical_requirement soft';
COMMENT ON COLUMN audit.evidence.requirement_tier_id IS
'The pinned tier it satisfies. @ref core.requirement_tier soft';
COMMENT ON COLUMN audit.evidence.control_id IS
'The pinned control it evidences. @ref core.control soft';
COMMENT ON COLUMN audit.evidence.evidence_specification_id IS
'The spec this fact fulfills. @ref core.evidence_specification soft';
COMMENT ON COLUMN audit.evidence.control_phase_code IS
'The lifecycle phase the evidence was captured at. @status reference.control_phase';
COMMENT ON COLUMN audit.evidence.evidence_artifact_type_code IS
'The artifact kind. @status reference.evidence_artifact_type';
COMMENT ON COLUMN audit.evidence.executable_version_id IS
'The version that produced the evidence. @ref core.executable_version soft';
COMMENT ON COLUMN audit.evidence.run_id IS
'The run that produced it. @ref core.execution_run soft';
COMMENT ON COLUMN audit.evidence.decision_log_id IS
'The decision that produced it. @ref audit.decision_log soft';
COMMENT ON COLUMN audit.evidence.storage_ref IS
'Where the artifact lives — connector + locator + digest.';
COMMENT ON COLUMN audit.evidence.produced_by_actor_id IS
'Who/what produced it — automation for auto-captured, a human for attested (D6). @ref core.actor soft';
COMMENT ON COLUMN audit.evidence.produced_role_code IS
'The capacity it was produced under. @status reference.role';
COMMENT ON COLUMN audit.evidence.created_at IS
'When captured; the partition key.';
