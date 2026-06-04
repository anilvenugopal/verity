-- core.champion_assignment  ·  subject: lifecycle  ·  (table)

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
COMMENT ON TABLE core.champion_assignment IS
'The append-only champion pointer: assign and revoke events that replace v1''s mutable current_champion column. The current champion for an executable is the latest non-revoked assignment, resolved through the version (entity_champion_current). Tying the pointer to events keeps a full, auditable promotion history (D4).

@tier 1
@lifecycle append-only
@subject lifecycle
@decision D4';
CREATE INDEX ix_champion_assignment_version_time ON core.champion_assignment (executable_version_id, created_at DESC);
COMMENT ON COLUMN core.champion_assignment.champion_assignment_id IS
'Identity of the assign/revoke event.';
COMMENT ON COLUMN core.champion_assignment.executable_version_id IS
'The version being made, or unmade, champion. @ref core.executable_version hard';
COMMENT ON COLUMN core.champion_assignment.is_revocation IS
'True if this demotes the version rather than promoting it.';
COMMENT ON COLUMN core.champion_assignment.lifecycle_event_id IS
'The promotion transition that produced this assignment, when there is one. @ref core.lifecycle_event hard';
COMMENT ON COLUMN core.champion_assignment.reason IS
'Why the champion changed.';
COMMENT ON COLUMN core.champion_assignment.actor_id IS
'Who changed the champion. @ref core.actor hard';
COMMENT ON COLUMN core.champion_assignment.acting_role_code IS
'The capacity they acted in. @status reference.role';
COMMENT ON COLUMN core.champion_assignment.created_at IS
'When the assignment event occurred; the ordering key for the current champion.';
