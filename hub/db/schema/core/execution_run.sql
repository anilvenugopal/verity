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
COMMENT ON TABLE core.execution_run IS
'One governed execution of a champion executable_version — the spine that the dispatch
row (harness_dispatch), the event-sourced state (execution_run_status), and the decision
log all hang off. A run is created at submission and never mutated; its state lives in the
append-only status events and its dispatch/claim lifecycle lives in harness_dispatch
(ADR-0002, ADR-0010).

@tier 1
@lifecycle insert-only
@subject runs
@invariant immutable after submit; state is event-sourced in execution_run_status
@adr 0002
@adr 0010';
COMMENT ON COLUMN core.execution_run.execution_run_id IS
'Identity of the run; the correlation id every decision log, dispatch row, and execution event carries back to.';
COMMENT ON COLUMN core.execution_run.executable_version_id IS
'The immutable version that actually ran, pinned at submission so the run stays reproducible even after the champion advances or is deprecated (ADR-0002 replay). @ref core.executable_version hard';
COMMENT ON COLUMN core.execution_run.run_entity_kind IS
'Whether an agent or a task ran. Denormalized onto the run so dispatch and reporting never have to join executable_version to branch on it. @enum core.run_entity_kind';
COMMENT ON COLUMN core.execution_run.application_id IS
'The owning application (tenant-of-record); scopes quota enforcement, reporting, and app-team visibility for the run. @ref core.application hard';
COMMENT ON COLUMN core.execution_run.deployment_id IS
'The governed placement this run originated from, when there is one; null for ad-hoc or replay runs. Soft ref because a Tier-1 run record must outlive the deployment row it came from. @ref core.deployment soft';
COMMENT ON COLUMN core.execution_run.deployment_run_mode_code IS
'live/shadow/ab/locked carried onto the run so the decision log can be compared champion-vs-challenger without re-deriving the mode (ADR-0006). @status reference.deployment_run_mode';
COMMENT ON COLUMN core.execution_run.ab_sample IS
'When run_mode=ab, the sample-scope marker identifying which challenger A/B slice this run belongs to; null otherwise.';
COMMENT ON COLUMN core.execution_run.run_purpose_code IS
'Separates real governed traffic (production) from evaluation/replay runs so cost and reporting do not conflate test-harness runs with live ones. @status reference.run_purpose';
COMMENT ON COLUMN core.execution_run.business_context_key IS
'Caller-supplied correlation key (e.g. the ticker or claim id) that stitches the steps of one business workflow together across multiple runs.';
COMMENT ON COLUMN core.execution_run.submitted_at IS
'When the run was submitted to governance — the start of the dispatch outbox path (PCR §3.3).';
COMMENT ON COLUMN core.execution_run.submitted_by_actor_id IS
'Who submitted the run: the harness automation actor (one per cluster, D6) or a human for a manual/replay run. @ref core.actor hard';
COMMENT ON COLUMN core.execution_run.submitted_role_code IS
'The capacity the submitter acted in; pairs with submitted_by_actor_id for the run''s attribution (D6). @status reference.role';
CREATE INDEX ix_execution_run_version ON core.execution_run (executable_version_id);
CREATE INDEX ix_execution_run_context ON core.execution_run (business_context_key);
