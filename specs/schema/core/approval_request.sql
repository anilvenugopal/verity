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
COMMENT ON TABLE core.approval_request IS
'The general gating request used by BOTH lifecycle promotions and intake. Each request targets exactly one thing — an intake XOR an executable_version (an exclusive arc) — and collects per-role sign-offs (approval_signoff) until its quorum is met. status_code is the mutable current state; the transition history lives in audit.status_transition (D4, D5).

@tier 1
@lifecycle mutable
@subject lifecycle
@status reference.approval_request_kind
@status reference.approval_request_status
@invariant exactly one target: intake XOR executable_version
@decision D4
@decision D5';
CREATE INDEX ix_approval_request_status ON core.approval_request (status_code);
COMMENT ON COLUMN core.approval_request.approval_request_id IS
'Identity of the request.';
COMMENT ON COLUMN core.approval_request.request_kind_code IS
'What is being requested — intake/risk_reclassification/promote_*/retire. @status reference.approval_request_kind';
COMMENT ON COLUMN core.approval_request.status_code IS
'Mutable current state of the request; transitions are audited in audit.status_transition. @status reference.approval_request_status';
COMMENT ON COLUMN core.approval_request.target_intake_id IS
'The intake under review, when the request targets an intake (mutually exclusive with the version target). @ref core.intake hard';
COMMENT ON COLUMN core.approval_request.target_executable_version_id IS
'The version under review, when the request targets a promotion or retire (mutually exclusive with the intake target). @ref core.executable_version hard';
COMMENT ON COLUMN core.approval_request.opened_by_actor_id IS
'Who opened the request. @ref core.actor hard';
COMMENT ON COLUMN core.approval_request.opened_role_code IS
'The capacity they acted in. @status reference.role';
COMMENT ON COLUMN core.approval_request.created_at IS
'When the request was opened.';
COMMENT ON COLUMN core.approval_request.updated_at IS
'When the request last changed state.';
