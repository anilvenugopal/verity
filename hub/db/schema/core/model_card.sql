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
COMMENT ON TABLE core.model_card IS
'The model-card review lifecycle for an executable_version — the documentation artifact with its own state (draft/...), distinct from the executable''s lifecycle. state is mutable (C9, D4).

@tier 1
@lifecycle mutable
@subject validation
@status reference.model_card_state
@decision D4';
COMMENT ON COLUMN core.model_card.model_card_id IS
'Identity of the card.';
COMMENT ON COLUMN core.model_card.executable_version_id IS
'The version documented. @ref core.executable_version hard';
COMMENT ON COLUMN core.model_card.model_card_state_code IS
'Mutable review state of the card. @status reference.model_card_state';
COMMENT ON COLUMN core.model_card.content IS
'The model-card content.';
COMMENT ON COLUMN core.model_card.created_at IS
'When created.';
COMMENT ON COLUMN core.model_card.updated_at IS
'When last updated.';
COMMENT ON COLUMN core.model_card.created_by_actor_id IS
'Who created it. @ref core.actor hard';
COMMENT ON COLUMN core.model_card.created_role_code IS
'The capacity they acted in. @status reference.role';
