-- core.intake_artifact_plan  ·  subject: intake  ·  (table)

CREATE TABLE core.intake_artifact_plan (
    intake_artifact_plan_id uuid     NOT NULL DEFAULT uuidv7(),
    intake_id              uuid      NOT NULL,
    planned_kind_code      text      NOT NULL,                       -- agent|task -> reference.executable_kind
    planned_name           text      NOT NULL,
    artifact_plan_status_code text   NOT NULL DEFAULT 'proposed',    -- mutable (D4)
    realized_executable_version_id uuid,                              -- D5: the built version (when realized)
    created_at             timestamptz NOT NULL DEFAULT now(),
    updated_at             timestamptz NOT NULL DEFAULT now(),
    created_by_actor_id    uuid      NOT NULL,
    created_role_code      text      NOT NULL,
    CONSTRAINT pk_intake_artifact_plan PRIMARY KEY (intake_artifact_plan_id),
    CONSTRAINT fk_intake_plan_intake FOREIGN KEY (intake_id) REFERENCES core.intake (intake_id) ON DELETE CASCADE,
    CONSTRAINT fk_intake_plan_kind FOREIGN KEY (planned_kind_code) REFERENCES reference.executable_kind (code),
    CONSTRAINT fk_intake_plan_status FOREIGN KEY (artifact_plan_status_code) REFERENCES reference.artifact_plan_status (code),
    CONSTRAINT fk_intake_plan_realized FOREIGN KEY (realized_executable_version_id) REFERENCES core.executable_version (executable_version_id) ON DELETE RESTRICT,
    CONSTRAINT fk_intake_plan_created_by FOREIGN KEY (created_by_actor_id) REFERENCES core.actor (actor_id),
    CONSTRAINT fk_intake_plan_created_role FOREIGN KEY (created_role_code) REFERENCES reference.role (code));
CREATE INDEX ix_intake_artifact_plan_intake ON core.intake_artifact_plan (intake_id);
