"""Auth session endpoints (M1 — feature 002).

`POST /auth/mock` and `POST /auth/logout` are the working portal session flow. The Entra OIDC
endpoints (`/auth/login`, `/auth/callback`) are **scaffolds**: the real Authorization-Code + PKCE
flow (state/nonce mint, token exchange, ID-token validation via the still-stubbed
`EntraAuthenticator`) is deferred until a dev-tenant registration exists
(user-authentication.md FR-001..004a; research.md §3-4). Mock is the first-login path for now.

Session model (local-dev mock): the env principal is always ambient, so "log out" is expressed by
marking the session `logged_out`; `/me` honours that flag and reports unauthenticated until the next
`POST /auth/mock`. Direct API callers (tests) carry no session cookie, so the flag never affects them.
"""
from __future__ import annotations

from fastapi import APIRouter, Request
from fastapi.responses import JSONResponse, RedirectResponse

from verity.hub.auth.provisioning import jit_provision
from verity.hub.config import get_settings

router = APIRouter(tags=["auth"])


@router.get("/auth/login")
async def auth_login(next: str = "/") -> RedirectResponse:
    """[scaffold] Entra OIDC initiation. No Entra client is configured in mock-first local dev, so
    we return the user to /signin with a flag rather than minting a fake /authorize redirect. The
    real PKCE flow lands with the Entra slice."""
    settings = get_settings()
    flag = "use_mock" if settings.auth_mode == "mock" else "entra_not_configured"
    return RedirectResponse(url=f"/signin?error={flag}", status_code=302)


@router.get("/auth/callback")
async def auth_callback(
    code: str | None = None, state: str | None = None, error: str | None = None
) -> RedirectResponse:
    """[scaffold] Entra OIDC callback — deferred with /auth/login. Always returns to /signin."""
    return RedirectResponse(url="/signin?error=entra_not_configured", status_code=302)


@router.post("/auth/mock", response_model=None)
async def auth_mock(request: Request) -> dict[str, bool] | JSONResponse:
    """Establish a session for the configured synthetic principal. Local-dev only (404 otherwise).
    Mirrors MockAuthenticator's provisioning path so the actor exists before /me resolves it."""
    settings = get_settings()
    if not (settings.auth_mode == "mock" and settings.env == "local"):
        return JSONResponse(
            status_code=404,
            content={"code": "not_found", "detail": "mock auth unavailable", "request_id": "local-dev"},
        )
    async with request.app.state.pool.connection() as conn:
        actor_id = await jit_provision(
            conn,
            tenant_id=settings.mock_tenant_id,
            microsoft_oid=settings.mock_microsoft_oid,
            display_name=settings.mock_display_name,
            email=settings.mock_email,
            upn=None,
        )
    request.session["actor_id"] = actor_id
    request.session.pop("logged_out", None)
    return {"ok": True}


@router.post("/auth/logout")
async def auth_logout(request: Request) -> dict[str, bool]:
    """Portal sign-out: clear the session and mark it logged_out so /me reports unauthenticated."""
    request.session.clear()
    request.session["logged_out"] = True
    return {"ok": True}
