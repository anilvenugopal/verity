"""User preferences routes — actor-scoped, no special action required (any authenticated actor)."""
from __future__ import annotations

from fastapi import APIRouter, Depends, Request
from psycopg import AsyncConnection

from verity.hub.auth.dependencies import get_principal
from verity.hub.auth.models import Principal
from verity.hub.preferences import service
from verity.hub.preferences.models import PreferencesPatch, UserPreferences

router = APIRouter(tags=["preferences"])


async def get_conn(request: Request):
    async with request.app.state.pool.connection() as conn:
        yield conn


@router.get("/api/preferences", response_model=UserPreferences)
async def get_preferences(
    conn: AsyncConnection = Depends(get_conn),
    principal: Principal = Depends(get_principal),
) -> UserPreferences:
    return await service.get(conn, principal.actor_id)


@router.patch("/api/preferences", response_model=UserPreferences)
async def patch_preferences(
    body: PreferencesPatch,
    conn: AsyncConnection = Depends(get_conn),
    principal: Principal = Depends(get_principal),
) -> UserPreferences:
    return await service.patch(conn, principal.actor_id, body)
