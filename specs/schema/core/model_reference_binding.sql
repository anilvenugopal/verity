-- core.model_reference_binding  ·  subject: decisions  ·  (table)

CREATE TABLE core.model_reference_binding (
    model_reference_binding_id uuid  NOT NULL DEFAULT uuidv7(),
    model_reference_id  uuid        NOT NULL,
    model_id            uuid        NOT NULL,
    valid_from          timestamptz  NOT NULL DEFAULT now(),
    valid_to            timestamptz,                            -- NULL = current resolution
    reason              text,                                   -- e.g. 'claude-sonnet-4-6 EOL -> claude-sonnet-5'
    bound_by_actor_id   uuid        NOT NULL,
    bound_role_code     text        NOT NULL,
    created_at          timestamptz  NOT NULL DEFAULT now(),
    CONSTRAINT pk_model_reference_binding PRIMARY KEY (model_reference_binding_id),
    CONSTRAINT fk_mrb_reference FOREIGN KEY (model_reference_id) REFERENCES core.model_reference (model_reference_id) ON DELETE RESTRICT,
    CONSTRAINT fk_mrb_model FOREIGN KEY (model_id) REFERENCES core.model (model_id) ON DELETE RESTRICT,
    CONSTRAINT fk_mrb_bound_by FOREIGN KEY (bound_by_actor_id) REFERENCES core.actor (actor_id),
    CONSTRAINT fk_mrb_bound_role FOREIGN KEY (bound_role_code) REFERENCES reference.role (code));
COMMENT ON TABLE core.model_reference_binding IS 'tier:1 SCD-2. Which actual model a reference resolves to, over time. Central swap = close old + open new (NO package re-promotion); windows allow as-of resolution for past runs.';
CREATE UNIQUE INDEX uq_model_reference_binding_current ON core.model_reference_binding (model_reference_id) WHERE valid_to IS NULL;
