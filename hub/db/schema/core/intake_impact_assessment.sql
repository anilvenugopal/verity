-- core.intake_impact_assessment  ·  subject: intake  ·  (table)

CREATE TABLE core.intake_impact_assessment (
    intake_impact_assessment_id uuid NOT NULL DEFAULT uuidv7(),
    intake_id            uuid       NOT NULL,
    revision             integer     NOT NULL,                      -- 1,2,3… immutable revisions
    assessment           jsonb       NOT NULL,                      -- the impact write-up (structured)
    valid_from           timestamptz NOT NULL DEFAULT now(),        -- SCD-2 window
    valid_to             timestamptz NOT NULL DEFAULT '2099-12-31 00:00:00+00',                                -- 2099-12-31 = open (current)
    created_at           timestamptz NOT NULL DEFAULT now(),
    created_by_actor_id  uuid       NOT NULL,
    created_role_code    text       NOT NULL,
    CONSTRAINT pk_intake_impact_assessment PRIMARY KEY (intake_impact_assessment_id),
    CONSTRAINT fk_intake_impact_intake FOREIGN KEY (intake_id) REFERENCES core.intake (intake_id) ON DELETE CASCADE,
    CONSTRAINT fk_intake_impact_created_by FOREIGN KEY (created_by_actor_id) REFERENCES core.actor (actor_id),
    CONSTRAINT fk_intake_impact_created_role FOREIGN KEY (created_role_code) REFERENCES reference.role (code),
    CONSTRAINT uq_intake_impact_revision UNIQUE (intake_id, revision));
COMMENT ON TABLE core.intake_impact_assessment IS
'The audit-sensitive impact write-up for an intake — the one figure that KEEPS full history (the D4 exception to mutable figures). Each revision is an immutable SCD-2 row; the current revision is the open one (valid_to = 2099-12-31), exposed by intake_impact_assessment_current.

@tier 1
@lifecycle scd2
@subject intake
@decision D4';
COMMENT ON COLUMN core.intake_impact_assessment.intake_impact_assessment_id IS
'Identity of the revision row.';
COMMENT ON COLUMN core.intake_impact_assessment.intake_id IS
'The intake assessed. @ref core.intake hard';
COMMENT ON COLUMN core.intake_impact_assessment.revision IS
'Monotonic revision number; immutable and unique per intake.';
COMMENT ON COLUMN core.intake_impact_assessment.assessment IS
'The structured impact write-up for this revision.';
COMMENT ON COLUMN core.intake_impact_assessment.valid_from IS
'Start of the SCD-2 validity window.';
COMMENT ON COLUMN core.intake_impact_assessment.valid_to IS
'End of the window; the open row (2099-12-31) is the current revision.';
COMMENT ON COLUMN core.intake_impact_assessment.created_at IS
'When the revision was written.';
COMMENT ON COLUMN core.intake_impact_assessment.created_by_actor_id IS
'Who wrote it. @ref core.actor hard';
COMMENT ON COLUMN core.intake_impact_assessment.created_role_code IS
'The capacity they acted in. @status reference.role';
