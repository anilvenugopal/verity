-- core.intake_roi_assessment  ·  subject: intake  ·  (table)

CREATE TABLE core.intake_roi_assessment (
    intake_roi_assessment_id uuid    NOT NULL DEFAULT uuidv7(),
    intake_id              uuid      NOT NULL,
    scenario               text      NOT NULL DEFAULT 'base',
    roi                    jsonb      NOT NULL,                       -- ROI figures (mutable)
    locked                 boolean    NOT NULL DEFAULT false,         -- lock = mutable flag (was lock_event; transitions -> audit.status_transition)
    created_at             timestamptz NOT NULL DEFAULT now(),
    updated_at             timestamptz NOT NULL DEFAULT now(),
    updated_by_actor_id    uuid,
    updated_role_code      text,
    CONSTRAINT pk_intake_roi_assessment PRIMARY KEY (intake_roi_assessment_id),
    CONSTRAINT fk_intake_roi_intake FOREIGN KEY (intake_id) REFERENCES core.intake (intake_id) ON DELETE CASCADE,
    CONSTRAINT fk_intake_roi_updated_by FOREIGN KEY (updated_by_actor_id) REFERENCES core.actor (actor_id),
    CONSTRAINT uq_intake_roi_scenario UNIQUE (intake_id, scenario));
COMMENT ON TABLE core.intake_roi_assessment IS
'The ROI figures for an intake, per scenario — a revisable business-case figure. locked is a mutable flag (lock/unlock transitions audited in audit.status_transition) that freezes the figure once the business case is agreed (D4).

@tier 1
@lifecycle mutable
@subject intake
@decision D4';
COMMENT ON COLUMN core.intake_roi_assessment.intake_roi_assessment_id IS
'Identity of the ROI row.';
COMMENT ON COLUMN core.intake_roi_assessment.intake_id IS
'The intake assessed. @ref core.intake hard';
COMMENT ON COLUMN core.intake_roi_assessment.scenario IS
'ROI scenario; unique per intake.';
COMMENT ON COLUMN core.intake_roi_assessment.roi IS
'The ROI figures (revisable).';
COMMENT ON COLUMN core.intake_roi_assessment.locked IS
'Mutable flag freezing the figure; lock/unlock transitions go to audit.status_transition.';
COMMENT ON COLUMN core.intake_roi_assessment.created_at IS
'When created.';
COMMENT ON COLUMN core.intake_roi_assessment.updated_at IS
'When last updated.';
COMMENT ON COLUMN core.intake_roi_assessment.updated_by_actor_id IS
'Who last revised it. @ref core.actor hard';
COMMENT ON COLUMN core.intake_roi_assessment.updated_role_code IS
'The capacity they acted in. @status reference.role';
