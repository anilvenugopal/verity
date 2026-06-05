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
    target_application_id        uuid,                            -- onboarding target (FR-IN-015)
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
    -- fk_approval_request_target_application is deferred to core/_relationships.sql
    -- (application is created after approval_request, like target_intake).
    CONSTRAINT fk_approval_request_opened_by FOREIGN KEY (opened_by_actor_id)
        REFERENCES core.actor (actor_id) ON DELETE RESTRICT,
    CONSTRAINT fk_approval_request_opened_role FOREIGN KEY (opened_role_code)
        REFERENCES reference.role (code) ON DELETE RESTRICT,
    CONSTRAINT ck_approval_request_one_target
        CHECK ( (target_intake_id IS NOT NULL)::int
              + (target_executable_version_id IS NOT NULL)::int
              + (target_application_id IS NOT NULL)::int = 1 )
);
COMMENT ON TABLE core.approval_request IS
'The general gating request used by lifecycle promotions, intake, AND application onboarding. Each request targets exactly one thing — an intake, an executable_version, or an application (an exclusive arc) — and collects per-role sign-offs (approval_signoff) until its quorum is met. The quorum is computed per request_kind_code (e.g. application_onboarding -> AI Governance + business-owner-if-not-proposer; intake -> the tier-based set, FR-IN-005). status_code is the mutable current state; the transition history lives in audit.status_transition (D4, D5).

@tier 1
@lifecycle mutable
@subject lifecycle
@status reference.approval_request_kind
@status reference.approval_request_status
@invariant exactly one target: intake | executable_version | application
@decision D4
@decision D5';
CREATE INDEX ix_approval_request_status ON core.approval_request (status_code);
COMMENT ON COLUMN core.approval_request.approval_request_id IS
'Identity of the request.';
COMMENT ON COLUMN core.approval_request.request_kind_code IS
'What is being requested — application_onboarding/intake/risk_reclassification/business_change/promote_*/retire. @status reference.approval_request_kind';
COMMENT ON COLUMN core.approval_request.status_code IS
'Mutable current state of the request; transitions are audited in audit.status_transition. @status reference.approval_request_status';
COMMENT ON COLUMN core.approval_request.target_intake_id IS
'The intake under review, when the request targets an intake (mutually exclusive with the version target). @ref core.intake hard';
COMMENT ON COLUMN core.approval_request.target_executable_version_id IS
'The version under review, when the request targets a promotion or retire (mutually exclusive with the intake target). @ref core.executable_version hard';
COMMENT ON COLUMN core.approval_request.target_application_id IS
'The application under review, when the request targets onboarding (mutually exclusive with the other targets). @ref core.application hard';
COMMENT ON COLUMN core.approval_request.opened_by_actor_id IS
'Who opened the request. @ref core.actor hard';
COMMENT ON COLUMN core.approval_request.opened_role_code IS
'The capacity they acted in. @status reference.role';
COMMENT ON COLUMN core.approval_request.created_at IS
'When the request was opened.';
COMMENT ON COLUMN core.approval_request.updated_at IS
'When the request last changed state.';
