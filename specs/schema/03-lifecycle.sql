-- =====================================================================
-- 03-lifecycle.sql — Verity v2 hardened schema · core LIFECYCLE & APPROVALS
-- The 6-state lifecycle (event-sourced, D4) — draft, candidate, staging, challenger,
-- champion, deprecated. (v1's 7th state `shadow` is now a CHALLENGER run-mode, not a
-- state; deprecated is restorable via rollback.) Champion assignment (event-sourced),
-- and the general approval/gating mechanism used by BOTH lifecycle promotions and intake.
-- =====================================================================

-- ===== lifecycle_event (append-only state machine; D4) ===============
-- One immutable row per state transition of an executable_version. Current state
-- is the VIEW entity_lifecycle_current (no mutable lifecycle_state column anywhere).
-- Example rows for agent "underwriting-assistant" v1.2.0:
--   (null   -> draft)      "created"
--   (draft  -> candidate)  "ready for review"
--   (candidate -> staging) "validated"   (approval_request_id set)
--   (staging -> challenger) "evaluate in prod (shadow/ab modes set per deployment)"
--   (challenger -> champion) "won evaluation"  (approval_request_id set)
--   (champion -> deprecated) "superseded"   ... and (deprecated -> champion) "ROLLBACK"
CREATE TABLE core.lifecycle_event (
    lifecycle_event_id    uuid        NOT NULL DEFAULT uuidv7(),
    executable_version_id uuid        NOT NULL,
    from_state_code       text,                                 -- NULL on initial creation
    to_state_code         text        NOT NULL,
    approval_request_id   uuid,                                 -- gating approval (nullable)
    rationale             text        NOT NULL,
    detail                jsonb        NOT NULL DEFAULT '{}'::jsonb,
    actor_id              uuid        NOT NULL,                 -- D6
    acting_role_code      text        NOT NULL,
    created_at            timestamptz  NOT NULL DEFAULT now(),
    CONSTRAINT pk_lifecycle_event PRIMARY KEY (lifecycle_event_id),
    CONSTRAINT fk_lifecycle_event_version FOREIGN KEY (executable_version_id)
        REFERENCES core.executable_version (executable_version_id) ON DELETE RESTRICT,
    CONSTRAINT fk_lifecycle_event_from FOREIGN KEY (from_state_code)
        REFERENCES reference.lifecycle_state (code) ON DELETE RESTRICT,
    CONSTRAINT fk_lifecycle_event_to FOREIGN KEY (to_state_code)
        REFERENCES reference.lifecycle_state (code) ON DELETE RESTRICT,
    CONSTRAINT fk_lifecycle_event_actor FOREIGN KEY (actor_id)
        REFERENCES core.actor (actor_id) ON DELETE RESTRICT,
    CONSTRAINT fk_lifecycle_event_acting_role FOREIGN KEY (acting_role_code)
        REFERENCES reference.role (code) ON DELETE RESTRICT,
    -- approval_request FK added below (after approval_request is created)
    CONSTRAINT ck_lifecycle_event_no_self_loop CHECK (from_state_code IS NULL OR from_state_code <> to_state_code)
);
COMMENT ON TABLE core.lifecycle_event IS 'tier:1 append-only. One executable_version state transition per row; current state via entity_lifecycle_current. D4.';
CREATE INDEX ix_lifecycle_event_version_time ON core.lifecycle_event (executable_version_id, created_at DESC);

CREATE VIEW core.entity_lifecycle_current AS
SELECT DISTINCT ON (executable_version_id)
       executable_version_id, to_state_code AS lifecycle_state_code, created_at AS since
FROM   core.lifecycle_event
ORDER  BY executable_version_id, created_at DESC;
COMMENT ON VIEW core.entity_lifecycle_current IS 'Current lifecycle state per executable_version (latest transition). D4.';

-- ===== champion_assignment (append-only champion pointer; D4) =========
-- Replaces v1 mutable agent.current_champion_version_id. Champion = the latest
-- non-revoked assignment for the executable (resolved through the version).
CREATE TABLE core.champion_assignment (
    champion_assignment_id uuid       NOT NULL DEFAULT uuidv7(),
    executable_version_id  uuid       NOT NULL,                 -- the version made champion
    is_revocation          boolean     NOT NULL DEFAULT false,  -- demotion event
    lifecycle_event_id     uuid,                                 -- the promotion transition (nullable)
    reason                 text,
    actor_id               uuid       NOT NULL,
    acting_role_code       text       NOT NULL,
    created_at             timestamptz NOT NULL DEFAULT now(),
    CONSTRAINT pk_champion_assignment PRIMARY KEY (champion_assignment_id),
    CONSTRAINT fk_champion_assignment_version FOREIGN KEY (executable_version_id)
        REFERENCES core.executable_version (executable_version_id) ON DELETE RESTRICT,
    CONSTRAINT fk_champion_assignment_event FOREIGN KEY (lifecycle_event_id)
        REFERENCES core.lifecycle_event (lifecycle_event_id) ON DELETE RESTRICT,
    CONSTRAINT fk_champion_assignment_actor FOREIGN KEY (actor_id)
        REFERENCES core.actor (actor_id) ON DELETE RESTRICT,
    CONSTRAINT fk_champion_assignment_acting_role FOREIGN KEY (acting_role_code)
        REFERENCES reference.role (code) ON DELETE RESTRICT
);
COMMENT ON TABLE core.champion_assignment IS 'tier:1 append-only. Champion pointer events (assign/revoke). Current champion via entity_champion_current. Replaces v1 mutable champion column (D4/C6).';
CREATE INDEX ix_champion_assignment_version_time ON core.champion_assignment (executable_version_id, created_at DESC);

-- current champion version per executable (resolved via the version's executable_id)
CREATE VIEW core.entity_champion_current AS
SELECT executable_id, executable_version_id
FROM (
    SELECT DISTINCT ON (ev.executable_id)
           ev.executable_id, ca.executable_version_id, ca.is_revocation
    FROM   core.champion_assignment ca
    JOIN   core.executable_version ev ON ev.executable_version_id = ca.executable_version_id
    ORDER  BY ev.executable_id, ca.created_at DESC
) latest
WHERE NOT is_revocation;
COMMENT ON VIEW core.entity_champion_current IS 'Current champion executable_version per executable (latest non-revoked assignment). D4.';

-- ===== approval_request (general gating; status mutable per D4) =======
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

-- now wire lifecycle_event.approval_request_id -> approval_request
ALTER TABLE core.lifecycle_event
    ADD CONSTRAINT fk_lifecycle_event_approval_request
    FOREIGN KEY (approval_request_id) REFERENCES core.approval_request (approval_request_id) ON DELETE RESTRICT;

-- ===== approval_signoff (append-only audit fact; D4/D6) ==============
-- One immutable per-approver sign-off. signed_as_role_code = the capacity signed in
-- (must be an approval role the approver actually holds; enforced server-side).
CREATE TABLE core.approval_signoff (
    approval_signoff_id uuid        NOT NULL DEFAULT uuidv7(),
    approval_request_id uuid        NOT NULL,
    approver_actor_id   uuid        NOT NULL,
    signed_as_role_code text        NOT NULL,                   -- reference.role; must be is_approval_role (app-enforced)
    decision_code       text        NOT NULL,
    comment             text,
    created_at          timestamptz  NOT NULL DEFAULT now(),
    CONSTRAINT pk_approval_signoff PRIMARY KEY (approval_signoff_id),
    CONSTRAINT fk_approval_signoff_request FOREIGN KEY (approval_request_id)
        REFERENCES core.approval_request (approval_request_id) ON DELETE RESTRICT,
    CONSTRAINT fk_approval_signoff_approver FOREIGN KEY (approver_actor_id)
        REFERENCES core.actor (actor_id) ON DELETE RESTRICT,
    CONSTRAINT fk_approval_signoff_role FOREIGN KEY (signed_as_role_code)
        REFERENCES reference.role (code) ON DELETE RESTRICT,
    CONSTRAINT fk_approval_signoff_decision FOREIGN KEY (decision_code)
        REFERENCES reference.approval_decision (code) ON DELETE RESTRICT,
    CONSTRAINT uq_approval_signoff_request_role UNIQUE (approval_request_id, signed_as_role_code)
);
COMMENT ON TABLE core.approval_signoff IS 'tier:1 append-only audit fact. Per-approver sign-off keyed by the required role filled (signed_as_role_code), by a real actor (FR-018/D6). One sign-off per required role per request.';
CREATE INDEX ix_approval_signoff_request ON core.approval_signoff (approval_request_id);
