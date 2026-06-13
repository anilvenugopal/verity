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
COMMENT ON TABLE core.deployment_event IS
'The append-only audit of every governed deployment operation and its outcome — including rejected requests. This is the inventory of what was attempted and what happened (deploy/promote/lock/cleanup/rollback against requested/rejected/succeeded/failed/superseded), so the platform can always say what is, and was, running where (ADR-0006).

@tier 1
@lifecycle append-only
@subject deploy
@status reference.deployment_operation
@status reference.deployment_outcome
@decision D8
@adr 0006';
CREATE INDEX ix_deployment_event_deployment ON core.deployment_event (deployment_id, created_at DESC);
COMMENT ON COLUMN core.deployment_event.deployment_event_id IS
'Identity of the event.';
COMMENT ON COLUMN core.deployment_event.deployment_id IS
'The deployment acted on; null when the request was rejected before a deployment existed. @ref core.deployment hard';
COMMENT ON COLUMN core.deployment_event.package_id IS
'The package the operation concerned. @ref core.package hard';
COMMENT ON COLUMN core.deployment_event.deployment_operation_code IS
'What was attempted — deploy_*/promote_champion/lock_deprecated/cleanup_deprecated/rollback. @status reference.deployment_operation';
COMMENT ON COLUMN core.deployment_event.deployment_outcome_code IS
'How it ended — requested/rejected_*/succeeded/failed/superseded; rejections are recorded, not discarded. @status reference.deployment_outcome';
COMMENT ON COLUMN core.deployment_event.detail IS
'Operation context — e.g. the rejection reason or the resolved image digest.';
COMMENT ON COLUMN core.deployment_event.actor_id IS
'Who performed the operation. @ref core.actor hard';
COMMENT ON COLUMN core.deployment_event.acting_role_code IS
'The capacity they acted in. @status reference.role';
COMMENT ON COLUMN core.deployment_event.created_at IS
'When the operation was recorded.';
