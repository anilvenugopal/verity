-- core.application  ·  subject: intake  ·  (table)

-- 04-intake.sql — Verity v2 hardened schema · core INTAKE
-- Application onboarding, the intake/risk machine, requirements, the
-- impact assessment (KEEPS history), plan/estimate/ROI/cost (mutable figures),
-- the obligation -> compliance hand-off, and per-application app-team grants.
-- Re-applied per D4 (event/lock collapse; impact-assessment exception), D5, D6, D9.
CREATE TABLE core.application (
    application_id      uuid        NOT NULL DEFAULT uuidv7(),
    name                text        NOT NULL,
    description         text,
    created_at          timestamptz  NOT NULL DEFAULT now(),
    updated_at          timestamptz  NOT NULL DEFAULT now(),
    created_by_actor_id uuid        NOT NULL,
    created_role_code   text        NOT NULL,
    CONSTRAINT pk_application PRIMARY KEY (application_id),
    CONSTRAINT fk_application_created_by FOREIGN KEY (created_by_actor_id) REFERENCES core.actor (actor_id),
    CONSTRAINT fk_application_created_role FOREIGN KEY (created_role_code) REFERENCES reference.role (code),
    CONSTRAINT uq_application_name UNIQUE (name),
    CONSTRAINT ck_application_name_not_blank CHECK (length(btrim(name)) > 0));
COMMENT ON TABLE core.application IS 'tier:1. Business application that owns intakes/use-cases and (via app-team grants) its own team.';
