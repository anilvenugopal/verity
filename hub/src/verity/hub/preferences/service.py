from __future__ import annotations

import json
from uuid import UUID

from psycopg import AsyncConnection

from verity.hub.db import queries
from verity.hub.preferences.models import PreferencesPatch, UserPreferences


async def get(conn: AsyncConnection, actor_id: UUID) -> UserPreferences:
    row = await queries.get_preferences(conn, actor_id=str(actor_id))
    if row is None:
        return UserPreferences()
    prefs = row["prefs"] or {}
    return UserPreferences(**{k: v for k, v in prefs.items() if v is not None})


async def patch(conn: AsyncConnection, actor_id: UUID, changes: PreferencesPatch) -> UserPreferences:
    delta = {k: v for k, v in changes.model_dump().items() if v is not None}
    row = await queries.upsert_preferences(
        conn, actor_id=str(actor_id), prefs=json.dumps(delta)
    )
    prefs = row["prefs"] or {}
    return UserPreferences(**{k: v for k, v in prefs.items() if v is not None})
