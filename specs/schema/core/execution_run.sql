-- core.execution_run  ·  subject: runs  ·  (table)

CREATE TABLE core.execution_run (
    execution_run_id        uuid       NOT NULL DEFAULT uuidv7(),
    executable_version_id   uuid       NOT NULL,                 -- the version that ran (FK to core)
    run_entity_kind         core.run_entity_kind NOT NULL,
    application_id          uuid       NOT NULL,
    deployment_id           uuid,                                 -- soft -> core deployment (08)
    deployment_run_mode_code text,                                -- live|shadow|ab|locked (FK to reference in 08)
    ab_sample               text,                                 -- A/B sample scope marker (when run_mode=ab)
    run_purpose_code        text       NOT NULL DEFAULT 'production',
    business_context_key    text,                                 -- e.g. the ticker (links workflow steps)
    submitted_at            timestamptz NOT NULL DEFAULT now(),
    submitted_by_actor_id   uuid       NOT NULL,                 -- the AUTOMATION actor (harness) or human
    submitted_role_code     text       NOT NULL,
    CONSTRAINT pk_execution_run PRIMARY KEY (execution_run_id),
    CONSTRAINT fk_execution_run_version FOREIGN KEY (executable_version_id)
        REFERENCES core.executable_version (executable_version_id) ON DELETE RESTRICT,
    CONSTRAINT fk_execution_run_application FOREIGN KEY (application_id)
        REFERENCES core.application (application_id) ON DELETE RESTRICT,
    CONSTRAINT fk_execution_run_purpose FOREIGN KEY (run_purpose_code) REFERENCES reference.run_purpose (code),
    CONSTRAINT fk_execution_run_submitted_by FOREIGN KEY (submitted_by_actor_id) REFERENCES core.actor (actor_id),
    CONSTRAINT fk_execution_run_submitted_role FOREIGN KEY (submitted_role_code) REFERENCES reference.role (code));
COMMENT ON TABLE core.execution_run IS 'tier:1. A governed run of an executable_version. Carries deployment_run_mode + ab_sample (A/B tagging). State is event-sourced in execution_run_status. ADR-0002/PCR.';
CREATE INDEX ix_execution_run_version ON core.execution_run (executable_version_id);
CREATE INDEX ix_execution_run_context ON core.execution_run (business_context_key);
