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
COMMENT ON TABLE core.hitl_override IS
'An additive, per-field human correction to a decision: the reviewer keeps the AI''s original value, supplies an override, and records why. Overrides never mutate the decision; they are appended as their own audited facts, anchored to the Tier-2 decision_log by soft ref and attributed to the human reviewer, never to the harness (D6).

@tier 1
@lifecycle append-only
@subject decisions
@decision D6';
COMMENT ON COLUMN core.hitl_override.hitl_override_id IS
'Identity of the override.';
COMMENT ON COLUMN core.hitl_override.decision_log_id IS
'The decision being corrected; soft ref across the Tier-1/Tier-2 boundary to the canonical record. @ref audit.decision_log soft';
COMMENT ON COLUMN core.hitl_override.field_path IS
'Which output field was overridden (a path into the decision output), so corrections are precise and additive rather than wholesale.';
COMMENT ON COLUMN core.hitl_override.original_value IS
'The AI value before the override, retained for audit and disagreement analysis.';
COMMENT ON COLUMN core.hitl_override.override_value IS
'The human-supplied replacement that downstream consumers should use in place of the original.';
COMMENT ON COLUMN core.hitl_override.reason IS
'The reviewer justification — a first-class audit fact for a regulated override.';
COMMENT ON COLUMN core.hitl_override.actor_id IS
'The human who made the correction; HITL is never an automation actor (D6). @ref core.actor hard';
COMMENT ON COLUMN core.hitl_override.acting_role_code IS
'The capacity the human acted in. @status reference.role';
COMMENT ON COLUMN core.hitl_override.created_at IS
'When the override was recorded.';
