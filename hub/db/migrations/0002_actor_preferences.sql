-- 0002_actor_preferences
-- Per-actor user preferences. JSONB blob; schema-less — new keys added forward, defaults
-- live in the API layer. One row per actor, created on first write (upsert).
CREATE TABLE core.actor_preferences (
    actor_id   uuid PRIMARY KEY REFERENCES core.actor (actor_id) ON DELETE CASCADE,
    prefs      jsonb NOT NULL DEFAULT '{}',
    updated_at timestamptz NOT NULL DEFAULT now()
);
