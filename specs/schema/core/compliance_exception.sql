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
COMMENT ON TABLE core.compliance_exception IS 'tier:1 first-class audit. A controlled, time-boxed waiver of a requirement tier: compensating controls, named approver (approve_exception), expiry. status mutable (D4); approving role = compliance/security. ADR-0008.';
CREATE INDEX ix_compliance_exception_requirement ON core.compliance_exception (canonical_requirement_id);
CREATE INDEX ix_compliance_exception_expiry ON core.compliance_exception (expires_at) WHERE exception_status_code = 'approved';
