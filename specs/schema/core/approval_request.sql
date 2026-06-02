-- core.approval_request  ·  subject: lifecycle  ·  (table)

-- Used by lifecycle promotions AND intake. Target is exactly one of an intake or an
-- executable_version (exclusive arc; only two target kinds). status_code is mutable;
-- transition history goes to audit.status_transition (see audit domain).
CREATE TABLE core.approval_request (
    approval_request_id          uuid        NOT NULL DEFAULT uuidv7(),
    request_kind_code            text        NOT NULL,           -- intake|risk_reclassification|promote_*|retire
    status_code                  text        NOT NULL DEFAULT 'pending',
    target_intake_id             uuid,                            -- FK -> core.intake added in 04-intake
    target_executable_version_id uuid,
    opened_by_actor_id           uuid        NOT NULL,
    opened_role_code             text        NOT NULL,
    created_at                   timestamptz  NOT NULL DEFAULT now(),
    updated_at                   timestamptz  NOT NULL DEFAULT now(),
    CONSTRAINT pk_approval_request PRIMARY KEY (approval_request_id),
    CONSTRAINT fk_approval_request_kind FOREIGN KEY (request_kind_code)
        REFERENCES reference.approval_request_kind (code) ON DELETE RESTRICT,
    CONSTRAINT fk_approval_request_status FOREIGN KEY (status_code)
        REFERENCES reference.approval_request_status (code) ON DELETE RESTRICT,
    CONSTRAINT fk_approval_request_target_version FOREIGN KEY (target_executable_version_id)
        REFERENCES core.executable_version (executable_version_id) ON DELETE RESTRICT,
    CONSTRAINT fk_approval_request_opened_by FOREIGN KEY (opened_by_actor_id)
        REFERENCES core.actor (actor_id) ON DELETE RESTRICT,
    CONSTRAINT fk_approval_request_opened_role FOREIGN KEY (opened_role_code)
        REFERENCES reference.role (code) ON DELETE RESTRICT,
    CONSTRAINT ck_approval_request_one_target
        CHECK ((target_intake_id IS NOT NULL) <> (target_executable_version_id IS NOT NULL))
);
COMMENT ON TABLE core.approval_request IS 'tier:1. General gating request (lifecycle promotions + intake). Exactly one target (intake XOR executable_version). status_code mutable; history in audit.status_transition. D4/D5.';
CREATE INDEX ix_approval_request_status ON core.approval_request (status_code);
