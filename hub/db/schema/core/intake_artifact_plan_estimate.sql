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
COMMENT ON TABLE core.intake_artifact_plan_estimate IS
'A cost/effort forecast for a planned artifact, per scenario (base/optimistic/...). A revisable figure (not history-kept), optionally tied to the model it was estimated against.

@tier 1
@lifecycle mutable
@subject intake';
COMMENT ON COLUMN core.intake_artifact_plan_estimate.intake_artifact_plan_estimate_id IS
'Identity of the estimate.';
COMMENT ON COLUMN core.intake_artifact_plan_estimate.intake_artifact_plan_id IS
'The plan being estimated. @ref core.intake_artifact_plan hard';
COMMENT ON COLUMN core.intake_artifact_plan_estimate.scenario IS
'Estimate scenario; unique per plan.';
COMMENT ON COLUMN core.intake_artifact_plan_estimate.estimate IS
'The cost/effort forecast (revisable).';
COMMENT ON COLUMN core.intake_artifact_plan_estimate.model_id IS
'The model the estimate assumes, when applicable. @ref core.model hard';
COMMENT ON COLUMN core.intake_artifact_plan_estimate.created_at IS
'When created.';
COMMENT ON COLUMN core.intake_artifact_plan_estimate.updated_at IS
'When last updated.';
COMMENT ON COLUMN core.intake_artifact_plan_estimate.updated_by_actor_id IS
'Who last revised it. @ref core.actor hard';
COMMENT ON COLUMN core.intake_artifact_plan_estimate.updated_role_code IS
'The capacity they acted in. @status reference.role';
