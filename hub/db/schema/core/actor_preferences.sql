-- core.actor_preferences  ·  subject: identity  ·  (table)

CREATE TABLE core.actor_preferences (
    actor_id   uuid        NOT NULL,
    prefs      jsonb       NOT NULL DEFAULT '{}',
    updated_at timestamptz NOT NULL DEFAULT now(),
    CONSTRAINT pk_actor_preferences PRIMARY KEY (actor_id),
    CONSTRAINT fk_actor_preferences_actor FOREIGN KEY (actor_id)
        REFERENCES core.actor (actor_id) ON DELETE CASCADE);
COMMENT ON TABLE core.actor_preferences IS
'Per-actor user preferences as a schema-less JSONB blob. One row per actor created on first write (upsert). New preference keys are added forward; defaults live in the API layer.

@tier 1
@lifecycle mutable
@subject identity';
COMMENT ON COLUMN core.actor_preferences.actor_id IS
'The actor these preferences belong to. @ref core.actor hard';
COMMENT ON COLUMN core.actor_preferences.prefs IS
'Preference bag — schema-less; keys added forward, defaults in the API layer.';
COMMENT ON COLUMN core.actor_preferences.updated_at IS
'When preferences were last written.';
