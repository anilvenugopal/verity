"""FastAPI app factory for the hub: health + DB readiness + auth wiring.

Auth is action-gated and fail-closed (user-authentication.md). Mock mode is local-dev only,
enforced at startup. Routers (intake, gateway, …) are added on top.
"""
from __future__ import annotations

import logging
from contextlib import asynccontextmanager

from fastapi import Depends, FastAPI, Request
from fastapi.responses import JSONResponse
from starlette.middleware.sessions import SessionMiddleware

from verity.hub.auth.dependencies import get_principal, require_action
from verity.hub.auth.models import AuthContext, AuthError, Principal
from verity.hub.auth.session import router as session_router
from verity.hub.config import get_settings, validate_startup
from verity.hub.db import make_pool, queries
from verity.hub.application.router import router as application_router
from verity.hub.approval.router import router as approval_router
from verity.hub.assessment.router import router as assessment_router
from verity.hub.intake.router import router as intake_router
from verity.hub.intake_approval.router import router as intake_approval_router

# Local-dev fallback so SessionMiddleware has a key when session_secret is unset (mock/local).
# Prod requires a real per-env secret — enforced in config.validate_startup (FR-013a).
_DEV_SESSION_SECRET = "local-dev-insecure-session-secret-change-me"

logger = logging.getLogger("verity.hub")


@asynccontextmanager
async def lifespan(app: FastAPI):
    settings = get_settings()
    validate_startup(settings)  # fail-closed (FR-030 / NFR-001a) before serving
    if settings.auth_mode == "mock":
        logger.warning("AUTH MODE = MOCK (local-dev only). Synthetic principal: roles=%s", settings.mock_roles)
    app.state.pool = make_pool(settings.database_url)
    await app.state.pool.open()
    try:
        yield
    finally:
        await app.state.pool.close()


def create_app() -> FastAPI:
    app = FastAPI(title="Verity Hub", version="0.1.0", lifespan=lifespan)
    settings = get_settings()
    app.add_middleware(
        SessionMiddleware,
        secret_key=settings.session_secret or _DEV_SESSION_SECRET,
        same_site="lax",
        https_only=settings.env != "local",
    )

    @app.exception_handler(AuthError)
    async def _auth_error(request: Request, exc: AuthError):  # 401 unauth / 403 denied, non-leaking
        return JSONResponse(
            status_code=exc.status_code,
            content={"code": exc.code, "detail": exc.detail,
                     "request_id": request.headers.get("x-request-id", "local-dev")},
        )

    @app.get("/healthz", tags=["health"])
    async def healthz() -> dict[str, str]:
        return {"status": "ok"}

    @app.get("/readyz", tags=["health"])
    async def readyz() -> dict[str, object]:
        async with app.state.pool.connection() as conn:
            roles = (await queries.count_roles(conn))["n"]
        return {"status": "ready", "reference_roles": roles}

    @app.get("/me", tags=["auth"])
    async def me(principal: Principal = Depends(get_principal)) -> dict[str, object]:
        # logged_out / mock-session resolution lives in get_principal now.
        s = get_settings()
        return {
            "actor_id": principal.actor_id,
            "display_name": principal.display_name,
            "email": principal.email,
            "platform_roles": sorted(principal.platform_roles),
            # app_team_roles surfaced in a later milestone (account-menu pills); empty for now.
            "app_team_roles": [],
            "is_mock": s.auth_mode == "mock",
        }

    # Example action-gated route: granting a platform role is security-only (FR-023).
    @app.get("/admin/roles", tags=["auth"])
    async def admin_roles(
        ctx: AuthContext = Depends(require_action("grant_platform_role")),
    ) -> dict[str, str]:
        return {"status": "authorized", "actor_id": ctx.principal.actor_id, "acting_role": ctx.acting_role}

    app.include_router(session_router)
    app.include_router(application_router)
    app.include_router(approval_router)
    app.include_router(intake_router)
    app.include_router(assessment_router)
    app.include_router(intake_approval_router)
    return app


app = create_app()
