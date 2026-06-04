"""FastAPI app factory for the hub. Skeleton: health + DB readiness.

Routers (intake, gateway, …) and auth (ADR-0003 / user-authentication) are added on top.
"""
from __future__ import annotations

from contextlib import asynccontextmanager

from fastapi import FastAPI

from .config import get_settings
from .db import make_pool, queries


@asynccontextmanager
async def lifespan(app: FastAPI):
    settings = get_settings()
    app.state.pool = make_pool(settings.database_url)
    await app.state.pool.open()
    try:
        yield
    finally:
        await app.state.pool.close()


def create_app() -> FastAPI:
    app = FastAPI(title="Verity Hub", version="0.1.0", lifespan=lifespan)

    @app.get("/healthz", tags=["health"])
    async def healthz() -> dict[str, str]:
        return {"status": "ok"}

    @app.get("/readyz", tags=["health"])
    async def readyz() -> dict[str, object]:
        async with app.state.pool.connection() as conn:
            roles = await queries.count_roles(conn)
        return {"status": "ready", "reference_roles": roles}

    return app


app = create_app()
