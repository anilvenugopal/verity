-- core.compliance_exception  ·  subject: compliance  ·  (table)

-- Renamed from reserved word `exception` -> compliance_exception (verification #7).
CREATE TABLE core.compliance_exception (
    compliance_exception_id uuid     NOT NULL DEFAULT uuidv7(),
    canonical_requirement_id uuid    NOT NULL,                    -- the requirement being excepted
    waived_tier_level     integer     NOT NULL,                   -- the tier waived
    scope_intake_id       uuid,                                    -- optional scope
    scope_application_id  uuid,
    exception_status_code text        NOT NULL DEFAULT 'requested',-- mutable (D4); transitions -> audit.status_transition
    approver_actor_id     uuid,                                    -- approve_exception action (compliance/security)
    signed_as_role_code   text,
    compensating_controls text        NOT NULL,                   -- what mitigates in the interim
    rationale             text        NOT NULL,
    expires_at            timestamptz  NOT NULL,                   -- max permitted duration
    opened_by_actor_id    uuid        NOT NULL,
    opened_role_code      text        NOT NULL,
    created_at            timestamptz  NOT NULL DEFAULT now(),
    updated_at            timestamptz  NOT NULL DEFAULT now(),
    CONSTRAINT pk_compliance_exception PRIMARY KEY (compliance_exception_id),
    CONSTRAINT fk_compliance_exception_requirement FOREIGN KEY (canonical_requirement_id) REFERENCES core.canonical_requirement (requirement_id) ON DELETE RESTRICT,
    CONSTRAINT fk_compliance_exception_intake FOREIGN KEY (scope_intake_id) REFERENCES core.intake (intake_id) ON DELETE RESTRICT,
    CONSTRAINT fk_compliance_exception_application FOREIGN KEY (scope_application_id) REFERENCES core.application (application_id) ON DELETE RESTRICT,
    CONSTRAINT fk_compliance_exception_status FOREIGN KEY (exception_status_code) REFERENCES reference.exception_status (code),
    CONSTRAINT fk_compliance_exception_approver FOREIGN KEY (approver_actor_id) REFERENCES core.actor (actor_id),
    CONSTRAINT fk_compliance_exception_signed_role FOREIGN KEY (signed_as_role_code) REFERENCES reference.role (code),
    CONSTRAINT fk_compliance_exception_opened_by FOREIGN KEY (opened_by_actor_id) REFERENCES core.actor (actor_id),
    CONSTRAINT fk_compliance_exception_opened_role FOREIGN KEY (opened_role_code) REFERENCES reference.role (code),
    CONSTRAINT ck_compliance_exception_tier CHECK (waived_tier_level >= 1));
COMMENT ON TABLE core.compliance_exception IS
'A controlled, time-boxed waiver of a requirement tier: the compensating controls that mitigate in the interim, a named approver (the approve_exception action, held by compliance/security), and a hard expiry. A first-class audit object — exceptions are governed, not hidden. status is the mutable current state (transitions audited in audit.status_transition) (ADR-0008, D4).

@tier 1
@lifecycle mutable
@subject compliance
@status reference.exception_status
@decision D4
@adr 0008';
CREATE INDEX ix_compliance_exception_requirement ON core.compliance_exception (canonical_requirement_id);
CREATE INDEX ix_compliance_exception_expiry ON core.compliance_exception (expires_at) WHERE exception_status_code = 'approved';
COMMENT ON COLUMN core.compliance_exception.compliance_exception_id IS
'Identity of the waiver.';
COMMENT ON COLUMN core.compliance_exception.canonical_requirement_id IS
'The requirement being excepted. @ref core.canonical_requirement hard';
COMMENT ON COLUMN core.compliance_exception.waived_tier_level IS
'The tier waived. At least 1.';
COMMENT ON COLUMN core.compliance_exception.scope_intake_id IS
'Optional intake scope of the waiver. @ref core.intake hard';
COMMENT ON COLUMN core.compliance_exception.scope_application_id IS
'Optional application scope of the waiver. @ref core.application hard';
COMMENT ON COLUMN core.compliance_exception.exception_status_code IS
'Mutable current state; transitions audited in audit.status_transition. @status reference.exception_status';
COMMENT ON COLUMN core.compliance_exception.approver_actor_id IS
'Who approved the waiver (approve_exception; compliance/security). @ref core.actor hard';
COMMENT ON COLUMN core.compliance_exception.signed_as_role_code IS
'The capacity the approver signed in. @status reference.role';
COMMENT ON COLUMN core.compliance_exception.compensating_controls IS
'What mitigates the risk while the waiver is in effect.';
COMMENT ON COLUMN core.compliance_exception.rationale IS
'Why the waiver was granted.';
COMMENT ON COLUMN core.compliance_exception.expires_at IS
'Hard expiry; the maximum permitted duration of the waiver.';
COMMENT ON COLUMN core.compliance_exception.opened_by_actor_id IS
'Who requested the waiver. @ref core.actor hard';
COMMENT ON COLUMN core.compliance_exception.opened_role_code IS
'The capacity they acted in. @status reference.role';
COMMENT ON COLUMN core.compliance_exception.created_at IS
'When opened.';
COMMENT ON COLUMN core.compliance_exception.updated_at IS
'When last updated.';
