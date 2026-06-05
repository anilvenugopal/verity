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
    data_classification_code text,                                  -- the intake's actual data sensitivity (set by the assessment Data tab); <= the app ceiling (FR-IN-018)
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
    CONSTRAINT fk_intake_data_classification FOREIGN KEY (data_classification_code) REFERENCES reference.data_classification (code),
    CONSTRAINT fk_intake_created_by FOREIGN KEY (created_by_actor_id) REFERENCES core.actor (actor_id),
    CONSTRAINT fk_intake_created_role FOREIGN KEY (created_role_code) REFERENCES reference.role (code));
COMMENT ON TABLE core.intake IS
'A single AI use-case under governance — the header the whole intake machine hangs off. Its EU-AI-Act risk tier and NAIC/internal materiality drive the obligation set it must satisfy. intake_status_code is the mutable current state; transitions are audited in audit.status_transition (D4).

@tier 1
@lifecycle mutable
@subject intake
@status reference.intake_status
@status reference.ai_risk_tier
@status reference.naic_materiality
@status reference.materiality_tier
@decision D4';
CREATE INDEX ix_intake_application ON core.intake (application_id);
CREATE INDEX ix_intake_status ON core.intake (intake_status_code);
COMMENT ON COLUMN core.intake.intake_id IS
'Identity of the use-case.';
COMMENT ON COLUMN core.intake.application_id IS
'The owning application. @ref core.application hard';
COMMENT ON COLUMN core.intake.title IS
'Human title of the use-case.';
COMMENT ON COLUMN core.intake.description IS
'What the use-case does.';
COMMENT ON COLUMN core.intake.intake_status_code IS
'Mutable current state; transition history lives in audit.status_transition. @status reference.intake_status';
COMMENT ON COLUMN core.intake.ai_risk_tier_code IS
'EU-AI-Act risk classification; a primary driver of the obligation set. @status reference.ai_risk_tier';
COMMENT ON COLUMN core.intake.naic_materiality_code IS
'NAIC materiality classification feeding obligations. @status reference.naic_materiality';
COMMENT ON COLUMN core.intake.materiality_tier_code IS
'Internal materiality tier. @status reference.materiality_tier';
COMMENT ON COLUMN core.intake.data_classification_code IS
'The intake''s actual data-sensitivity, declared by the assessment Data tab; MUST NOT exceed the owning application''s ceiling (FR-IN-018). Null until the Data tab is completed. @status reference.data_classification';
COMMENT ON COLUMN core.intake.created_at IS
'When created.';
COMMENT ON COLUMN core.intake.updated_at IS
'When last updated.';
COMMENT ON COLUMN core.intake.created_by_actor_id IS
'Who created it. @ref core.actor hard';
COMMENT ON COLUMN core.intake.created_role_code IS
'The capacity they acted in. @status reference.role';
