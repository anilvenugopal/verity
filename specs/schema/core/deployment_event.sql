-- core.deployment_event  ·  subject: deploy  ·  (table)

CREATE TABLE core.deployment_event (
    deployment_event_id   uuid       NOT NULL DEFAULT uuidv7(),
    deployment_id         uuid,                                  -- nullable for a rejected request
    package_id            uuid       NOT NULL,
    deployment_operation_code text   NOT NULL,                  -- deploy_*|promote_champion|lock_deprecated|cleanup_deprecated|rollback
    deployment_outcome_code text     NOT NULL,                  -- requested|rejected_*|succeeded|failed|superseded
    detail                jsonb      NOT NULL DEFAULT '{}'::jsonb,
    actor_id              uuid       NOT NULL,
    acting_role_code      text       NOT NULL,
    created_at            timestamptz NOT NULL DEFAULT now(),
    CONSTRAINT pk_deployment_event PRIMARY KEY (deployment_event_id),
    CONSTRAINT fk_deployment_event_deployment FOREIGN KEY (deployment_id) REFERENCES core.deployment (deployment_id) ON DELETE RESTRICT,
    CONSTRAINT fk_deployment_event_package FOREIGN KEY (package_id) REFERENCES core.package (package_id) ON DELETE RESTRICT,
    CONSTRAINT fk_deployment_event_operation FOREIGN KEY (deployment_operation_code) REFERENCES reference.deployment_operation (code),
    CONSTRAINT fk_deployment_event_outcome FOREIGN KEY (deployment_outcome_code) REFERENCES reference.deployment_outcome (code),
    CONSTRAINT fk_deployment_event_actor FOREIGN KEY (actor_id) REFERENCES core.actor (actor_id),
    CONSTRAINT fk_deployment_event_acting_role FOREIGN KEY (acting_role_code) REFERENCES reference.role (code));
COMMENT ON TABLE core.deployment_event IS 'tier:1 append-only. Governed deployment operations + outcome (the inventory/audit of deploy actions, incl. rejections). D8/ADR-0006.';
CREATE INDEX ix_deployment_event_deployment ON core.deployment_event (deployment_id, created_at DESC);
