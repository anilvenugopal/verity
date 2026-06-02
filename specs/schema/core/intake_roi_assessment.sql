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
