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
COMMENT ON TABLE core.application IS
'A business application under governance — the tenant-of-record that owns intakes and use-cases and, through per-application app-team grants, its own team. Quota, reporting, and run attribution all scope to it.

@tier 1
@lifecycle mutable
@subject intake';
COMMENT ON COLUMN core.application.application_id IS
'Identity of the application; the scoping key for intakes, app-team roles, quota and reporting.';
COMMENT ON COLUMN core.application.name IS
'Human name; unique and non-blank.';
COMMENT ON COLUMN core.application.description IS
'What the application is.';
COMMENT ON COLUMN core.application.created_at IS
'When onboarded.';
COMMENT ON COLUMN core.application.updated_at IS
'When last updated.';
COMMENT ON COLUMN core.application.created_by_actor_id IS
'Who onboarded it. @ref core.actor hard';
COMMENT ON COLUMN core.application.created_role_code IS
'The capacity they acted in (D6). @status reference.role';
