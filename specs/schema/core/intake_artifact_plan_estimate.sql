-- core.intake_artifact_plan_estimate  ·  subject: intake  ·  (table)

CREATE TABLE core.intake_artifact_plan_estimate (
    intake_artifact_plan_estimate_id uuid NOT NULL DEFAULT uuidv7(),
    intake_artifact_plan_id uuid    NOT NULL,
    scenario               text     NOT NULL DEFAULT 'base',
    estimate               jsonb     NOT NULL,                       -- cost/effort forecast (mutable figure)
    model_id               uuid,                                      -- FK -> core.model in 06-decisions
    created_at             timestamptz NOT NULL DEFAULT now(),
    updated_at             timestamptz NOT NULL DEFAULT now(),
    updated_by_actor_id    uuid,
    updated_role_code      text,
    CONSTRAINT pk_intake_artifact_plan_estimate PRIMARY KEY (intake_artifact_plan_estimate_id),
    CONSTRAINT fk_intake_estimate_plan FOREIGN KEY (intake_artifact_plan_id) REFERENCES core.intake_artifact_plan (intake_artifact_plan_id) ON DELETE CASCADE,
    CONSTRAINT fk_intake_estimate_updated_by FOREIGN KEY (updated_by_actor_id) REFERENCES core.actor (actor_id),
    CONSTRAINT uq_intake_estimate_scenario UNIQUE (intake_artifact_plan_id, scenario));
