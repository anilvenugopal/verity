-- core.application  ·  subject: intake  ·  (table)

-- 04-intake.sql — Verity v2 hardened schema · core INTAKE
-- Application onboarding, the intake/risk machine, requirements, the
-- impact assessment (KEEPS history), plan/estimate/ROI/cost (mutable figures),
-- the obligation -> compliance hand-off, and per-application app-team grants.
-- Re-applied per D4 (event/lock collapse; impact-assessment exception), D5, D6, D9.
CREATE TABLE core.application (
    application_id          uuid        NOT NULL DEFAULT uuidv7(),
    code                    text        NOT NULL,                       -- TLA, immutable once active (service-enforced)
    name                    text        NOT NULL,
    description             text        NOT NULL,
    application_status_code text        NOT NULL DEFAULT 'pending',     -- pending->active gate (FR-IN-015)
    line_of_business_code   text,                                       -- optional reporting/routing context
    data_classification_code text       NOT NULL,                       -- sensitivity CEILING (intake actual <= this)
    business_owner_actor_id uuid        NOT NULL,                       -- designated owner; approval-routing target
    affects_consumers       boolean     NOT NULL,                       -- explicit attestation (no default)
    processes_pii           boolean     NOT NULL,
    consumer_facing         boolean     NOT NULL,
    created_at              timestamptz  NOT NULL DEFAULT now(),
    updated_at              timestamptz  NOT NULL DEFAULT now(),
    created_by_actor_id     uuid        NOT NULL,
    created_role_code       text        NOT NULL,
    CONSTRAINT pk_application PRIMARY KEY (application_id),
    CONSTRAINT fk_application_created_by FOREIGN KEY (created_by_actor_id) REFERENCES core.actor (actor_id),
    CONSTRAINT fk_application_created_role FOREIGN KEY (created_role_code) REFERENCES reference.role (code),
    CONSTRAINT fk_application_status FOREIGN KEY (application_status_code) REFERENCES reference.application_status (code),
    CONSTRAINT fk_application_lob FOREIGN KEY (line_of_business_code) REFERENCES reference.line_of_business (code),
    CONSTRAINT fk_application_data_classification FOREIGN KEY (data_classification_code) REFERENCES reference.data_classification (code),
    CONSTRAINT fk_application_business_owner FOREIGN KEY (business_owner_actor_id) REFERENCES core.actor (actor_id),
    CONSTRAINT uq_application_name UNIQUE (name),
    CONSTRAINT uq_application_code UNIQUE (code),
    CONSTRAINT ck_application_code_tla CHECK (code ~ '^[A-Z]{3}$'),
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
COMMENT ON COLUMN core.application.code IS
'Three-letter acronym (TLA) — the stable audit-correlation key and the application_code resolution key (FR-IN-001). Unique; immutable once the application is active. @check ^[A-Z]{3}$';
COMMENT ON COLUMN core.application.application_status_code IS
'Lifecycle state; a non-active application cannot own promotable intakes/assets (FR-IN-015). @status reference.application_status';
COMMENT ON COLUMN core.application.line_of_business_code IS
'Optional insurance line for reporting/routing. @status reference.line_of_business';
COMMENT ON COLUMN core.application.data_classification_code IS
'The application-wide data-sensitivity CEILING; an intake''s actual classification must not exceed it, and processes_pii=true implies >= confidential (FR-IN-017/018). @status reference.data_classification';
COMMENT ON COLUMN core.application.business_owner_actor_id IS
'The designated business owner — the senior accountability and the approval-routing target (the owner must be proposer or approver). @ref core.actor hard';
COMMENT ON COLUMN core.application.affects_consumers IS
'Explicit attestation (no default): does the application drive automated decisions affecting consumers? Triggers EU-AI-Act/Colorado/NAIC scrutiny (FR-IN-017).';
COMMENT ON COLUMN core.application.processes_pii IS
'Explicit attestation (no default): does it process PII/PHI? Drives privacy obligations and the >= confidential ceiling rule.';
COMMENT ON COLUMN core.application.consumer_facing IS
'Explicit attestation (no default): is it consumer-facing? Drives disclosure/transparency obligations.';
