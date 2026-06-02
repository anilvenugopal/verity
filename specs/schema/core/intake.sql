-- core.intake  ·  subject: intake  ·  (table)

CREATE TABLE core.intake (
    intake_id            uuid        NOT NULL DEFAULT uuidv7(),
    application_id       uuid        NOT NULL,
    title                text        NOT NULL,
    description          text,
    intake_status_code   text        NOT NULL DEFAULT 'proposed',   -- mutable (D4); history -> audit.status_transition
    ai_risk_tier_code    text,                                       -- classification (drives obligations)
    naic_materiality_code text,
    materiality_tier_code text,
    created_at           timestamptz  NOT NULL DEFAULT now(),
    updated_at           timestamptz  NOT NULL DEFAULT now(),
    created_by_actor_id  uuid        NOT NULL,
    created_role_code    text        NOT NULL,
    CONSTRAINT pk_intake PRIMARY KEY (intake_id),
    CONSTRAINT fk_intake_application FOREIGN KEY (application_id) REFERENCES core.application (application_id) ON DELETE RESTRICT,
    CONSTRAINT fk_intake_status FOREIGN KEY (intake_status_code) REFERENCES reference.intake_status (code),
    CONSTRAINT fk_intake_risk_tier FOREIGN KEY (ai_risk_tier_code) REFERENCES reference.ai_risk_tier (code),
    CONSTRAINT fk_intake_naic FOREIGN KEY (naic_materiality_code) REFERENCES reference.naic_materiality (code),
    CONSTRAINT fk_intake_materiality FOREIGN KEY (materiality_tier_code) REFERENCES reference.materiality_tier (code),
    CONSTRAINT fk_intake_created_by FOREIGN KEY (created_by_actor_id) REFERENCES core.actor (actor_id),
    CONSTRAINT fk_intake_created_role FOREIGN KEY (created_role_code) REFERENCES reference.role (code));
COMMENT ON TABLE core.intake IS 'tier:1. Use-case intake header. intake_status_code mutable (D4; transitions in audit.status_transition). Risk/materiality drive the obligation set.';
CREATE INDEX ix_intake_application ON core.intake (application_id);
CREATE INDEX ix_intake_status ON core.intake (intake_status_code);
