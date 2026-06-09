-- Preferences queries (actor-scoped user preferences, JSONB blob).

-- name: get_preferences^
-- Returns the raw prefs blob for this actor, or NULL if they've never saved preferences.
SELECT prefs FROM core.actor_preferences WHERE actor_id = %(actor_id)s;

-- name: upsert_preferences^
-- Shallow-merge %(prefs)s into the stored blob (PostgreSQL || operator). First write creates
-- the row; subsequent writes preserve existing keys unless overwritten. Returns merged blob.
INSERT INTO core.actor_preferences (actor_id, prefs)
VALUES (%(actor_id)s, %(prefs)s::jsonb)
ON CONFLICT (actor_id) DO UPDATE
    SET prefs      = core.actor_preferences.prefs || %(prefs)s::jsonb,
        updated_at = now()
RETURNING prefs;
