-- core.lifecycle_event  ·  subject: lifecycle  ·  (table)

-- 03-lifecycle.sql — Verity v2 hardened schema · core LIFECYCLE & APPROVALS
-- The 6-state lifecycle (event-sourced, D4) — draft, candidate, staging, challenger,
-- champion, deprecated. (v1's 7th state `shadow` is now a CHALLENGER run-mode, not a
-- state; deprecated is restorable via rollback.) Champion assignment (event-sourced),
-- and the general approval/gating mechanism used by BOTH lifecycle promotions and intake.

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
