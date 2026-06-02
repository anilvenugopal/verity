-- core.hitl_override  ·  subject: decisions  ·  (table)

CREATE TABLE core.hitl_override (
    hitl_override_id    uuid        NOT NULL DEFAULT uuidv7(),
    decision_log_id     uuid        NOT NULL,                   -- soft ref -> audit.decision_log (Tier-2)
    field_path          text        NOT NULL,
    original_value      jsonb,
    override_value      jsonb       NOT NULL,
    reason              text        NOT NULL,
    actor_id            uuid        NOT NULL,                   -- the human (D6)
    acting_role_code    text        NOT NULL,
    created_at          timestamptz  NOT NULL DEFAULT now(),
    CONSTRAINT pk_hitl_override PRIMARY KEY (hitl_override_id),
    CONSTRAINT fk_hitl_override_actor FOREIGN KEY (actor_id) REFERENCES core.actor (actor_id),
    CONSTRAINT fk_hitl_override_acting_role FOREIGN KEY (acting_role_code) REFERENCES reference.role (code));
COMMENT ON TABLE core.hitl_override IS 'tier:1 append-only. Per-field human override on a decision (soft ref to the Tier-2 decision_log). Attributed to the human actor. D6.';
