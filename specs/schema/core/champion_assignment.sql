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
COMMENT ON TABLE core.champion_assignment IS 'tier:1 append-only. Champion pointer events (assign/revoke). Current champion via entity_champion_current. Replaces v1 mutable champion column (D4/C6).';
CREATE INDEX ix_champion_assignment_version_time ON core.champion_assignment (executable_version_id, created_at DESC);
