-- core.model_reference_binding  ·  subject: decisions  ·  (table)

CREATE TABLE core.model_reference_binding (
    model_reference_binding_id uuid  NOT NULL DEFAULT uuidv7(),
    model_reference_id  uuid        NOT NULL,
    model_id            uuid        NOT NULL,
    valid_from          timestamptz  NOT NULL DEFAULT now(),
    valid_to            timestamptz NOT NULL DEFAULT '2099-12-31 00:00:00+00',                            -- 2099-12-31 = open (current)
    reason              text,                                   -- e.g. 'claude-sonnet-4-6 EOL -> claude-sonnet-5'
    bound_by_actor_id   uuid        NOT NULL,
    bound_role_code     text        NOT NULL,
    created_at          timestamptz  NOT NULL DEFAULT now(),
    CONSTRAINT pk_model_reference_binding PRIMARY KEY (model_reference_binding_id),
    CONSTRAINT fk_mrb_reference FOREIGN KEY (model_reference_id) REFERENCES core.model_reference (model_reference_id) ON DELETE RESTRICT,
    CONSTRAINT fk_mrb_model FOREIGN KEY (model_id) REFERENCES core.model (model_id) ON DELETE RESTRICT,
    CONSTRAINT fk_mrb_bound_by FOREIGN KEY (bound_by_actor_id) REFERENCES core.actor (actor_id),
    CONSTRAINT fk_mrb_bound_role FOREIGN KEY (bound_role_code) REFERENCES reference.role (code));
COMMENT ON TABLE core.model_reference_binding IS
'Which actual model a reference resolves to, over time. A central model swap is just closing the open binding and opening a new one (no package re-promotion); the validity windows let a past run resolve the model that was bound as-of its execution (D10).

@tier 1
@lifecycle scd2
@subject decisions
@decision D10';
CREATE UNIQUE INDEX uq_model_reference_binding_current ON core.model_reference_binding (model_reference_id) WHERE valid_to = '2099-12-31 00:00:00+00';
COMMENT ON COLUMN core.model_reference_binding.model_reference_binding_id IS
'Identity of the binding window.';
COMMENT ON COLUMN core.model_reference_binding.model_reference_id IS
'The alias being bound. @ref core.model_reference hard';
COMMENT ON COLUMN core.model_reference_binding.model_id IS
'The actual model it resolves to in this window. @ref core.model hard';
COMMENT ON COLUMN core.model_reference_binding.valid_from IS
'Start of the SCD-2 validity window.';
COMMENT ON COLUMN core.model_reference_binding.valid_to IS
'End of the window; the open row (2099-12-31) is current.';
COMMENT ON COLUMN core.model_reference_binding.reason IS
'Why the binding changed, e.g. a model EOL or upgrade.';
COMMENT ON COLUMN core.model_reference_binding.bound_by_actor_id IS
'Who set the binding. @ref core.actor hard';
COMMENT ON COLUMN core.model_reference_binding.bound_role_code IS
'The capacity they acted in. @status reference.role';
COMMENT ON COLUMN core.model_reference_binding.created_at IS
'When the binding was recorded.';
