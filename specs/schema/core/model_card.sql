-- core.model_card  ·  subject: validation  ·  (table)

CREATE TABLE core.model_card (
    model_card_id uuid NOT NULL DEFAULT uuidv7(), executable_version_id uuid NOT NULL,
    model_card_state_code text NOT NULL DEFAULT 'draft', content jsonb NOT NULL,
    created_at timestamptz NOT NULL DEFAULT now(), updated_at timestamptz NOT NULL DEFAULT now(),
    created_by_actor_id uuid NOT NULL, created_role_code text NOT NULL,
    CONSTRAINT pk_model_card PRIMARY KEY (model_card_id),
    CONSTRAINT fk_model_card_version FOREIGN KEY (executable_version_id) REFERENCES core.executable_version (executable_version_id) ON DELETE RESTRICT,
    CONSTRAINT fk_model_card_state FOREIGN KEY (model_card_state_code) REFERENCES reference.model_card_state (code),
    CONSTRAINT fk_model_card_created_by FOREIGN KEY (created_by_actor_id) REFERENCES core.actor (actor_id),
    CONSTRAINT fk_model_card_created_role FOREIGN KEY (created_role_code) REFERENCES reference.role (code));
COMMENT ON TABLE core.model_card IS 'tier:1. Model-card review lifecycle; state mutable (D4). Distinct from the executable lifecycle. C9.';
