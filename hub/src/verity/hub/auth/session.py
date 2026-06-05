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

import uuid

from fastapi import APIRouter, Request
from fastapi.responses import JSONResponse, RedirectResponse
from pydantic import BaseModel

from verity.hub.auth.provisioning import jit_provision
from verity.hub.config import get_settings

router = APIRouter(tags=["auth"])

# A deterministic mock identity per role-set, so each persona is its own actor (clean separation,
# e.g. a submitter vs a distinct approver) without any DB role-grant bookkeeping.
_MOCK_OID_NS = uuid.UUID("00000000-0000-0000-0000-0000000000aa")


def _mock_oid(roles: list[str]) -> str:
    return str(uuid.uuid5(_MOCK_OID_NS, ",".join(sorted(roles))))


class MockLogin(BaseModel):
    roles: list[str] | None = None


def _mock_unavailable() -> JSONResponse:
    return JSONResponse(
        status_code=404,
        content={"code": "not_found", "detail": "mock auth unavailable", "request_id": "local-dev"},
    )


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


@router.get("/auth/roles", response_model=None)
async def auth_roles(request: Request) -> dict | JSONResponse:
    """The selectable role vocabulary for the mock sign-in screen (local-dev only)."""
    settings = get_settings()
    if not (settings.auth_mode == "mock" and settings.env == "local"):
        return _mock_unavailable()
    async with request.app.state.pool.connection() as conn:
        cur = await conn.execute("select code from reference.role order by code")
        rows = await cur.fetchall()
    return {"roles": [r["code"] for r in rows]}


@router.post("/auth/mock", response_model=None)
async def auth_mock(request: Request, body: MockLogin | None = None) -> dict | JSONResponse:
    """Establish a mock session with the roles chosen on the sign-in screen (local-dev only).

    The chosen roles are stored in the session and become the principal's roles — switching persona
    is just signing out and back in with a different set; no restart, no DB grants to accumulate.
    Falls back to the configured default roles when none are sent."""
    settings = get_settings()
    if not (settings.auth_mode == "mock" and settings.env == "local"):
        return _mock_unavailable()
    roles = sorted(set(body.roles)) if (body and body.roles) else list(settings.mock_roles)
    oid = _mock_oid(roles)
    display = f"Local Dev ({', '.join(roles)})"
    async with request.app.state.pool.connection() as conn:
        actor_id = await jit_provision(
            conn,
            tenant_id=settings.mock_tenant_id,
            microsoft_oid=oid,
            display_name=display,
            email=settings.mock_email,
            upn=None,
        )
    request.session.update(
        mock_actor_id=actor_id, mock_oid=oid, mock_roles=roles, mock_display_name=display
    )
    request.session.pop("logged_out", None)
    return {"ok": True, "roles": roles}


@router.post("/auth/logout")
async def auth_logout(request: Request) -> dict[str, bool]:
    """Portal sign-out: clear the session and mark it logged_out so /me reports unauthenticated."""
    request.session.clear()
    request.session["logged_out"] = True
    return {"ok": True}
