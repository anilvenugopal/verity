"""Auth session endpoints (feature 002).

Mock and Entra sign-in coexist in local dev:
  - `POST /auth/mock` — local-dev mock login; roles are chosen on the sign-in screen and stored in
    the session. `GET /auth/roles` serves the role vocabulary.
  - `GET /auth/login` / `GET /auth/callback` — the real Entra OIDC Authorization-Code + PKCE flow
    (state/nonce, code→token exchange, ID-token validation via JWKS), establishing a real session.
  - `POST /auth/logout` — clears the session and marks it `logged_out`.

Roles always come from Verity's DB (FR-007), never from the token. A fresh Entra user therefore has
no roles; in LOCAL DEV only, the first Entra sign-in is granted a default role set so the app is
usable immediately (a no-op once the user holds any role).
"""
from __future__ import annotations

import base64
import hashlib
import secrets
import urllib.parse
import uuid

import httpx
import jwt
from fastapi import APIRouter, Request
from fastapi.responses import JSONResponse, RedirectResponse
from jwt import PyJWKClient
from pydantic import BaseModel

from verity.hub.auth.provisioning import jit_provision
from verity.hub.config import Settings, get_settings
from verity.hub.db import queries

router = APIRouter(tags=["auth"])

# local-dev first-login grants (roles come from the DB, never the token — FR-007)
DEFAULT_LOGIN_ROLES = ["viewer"]                              # everyone: minimal, read-only
ADMIN_LOGIN_ROLES = ["ai_governance", "security", "viewer"]  # the configured admin: can administer

_MOCK_OID_NS = uuid.UUID("00000000-0000-0000-0000-0000000000aa")
_jwk_clients: dict[str, PyJWKClient] = {}


def _mock_oid(roles: list[str]) -> str:
    return str(uuid.uuid5(_MOCK_OID_NS, ",".join(sorted(roles))))


class MockLogin(BaseModel):
    roles: list[str] | None = None


def _mock_unavailable() -> JSONResponse:
    return JSONResponse(
        status_code=404,
        content={"code": "not_found", "detail": "mock auth unavailable", "request_id": "local-dev"},
    )


def _safe_next(raw: str | None) -> str:
    """Allow only same-app absolute paths as the post-login redirect (never an external URL)."""
    if raw and raw.startswith("/") and not raw.startswith("//"):
        return raw
    return "/"


# ── Entra OIDC ────────────────────────────────────────────────────────────────

def _authority(settings: Settings) -> str:
    return f"https://login.microsoftonline.com/{settings.entra_tenant_id}"


@router.get("/auth/login")
async def auth_login(request: Request, next: str = "/") -> RedirectResponse:
    """Begin Entra OIDC: mint state + nonce + PKCE, stash them in the session, redirect to
    /authorize. If Entra isn't configured, bounce back to /signin (use the mock card)."""
    settings = get_settings()
    if not settings.entra_configured:
        flag = "use_mock" if settings.auth_mode == "mock" else "entra_not_configured"
        return RedirectResponse(url=f"/signin?error={flag}", status_code=302)

    state = secrets.token_urlsafe(32)
    nonce = secrets.token_urlsafe(32)
    verifier = secrets.token_urlsafe(64)
    challenge = base64.urlsafe_b64encode(hashlib.sha256(verifier.encode()).digest()).rstrip(b"=").decode()
    request.session["oidc"] = {"state": state, "nonce": nonce, "verifier": verifier, "next": _safe_next(next)}

    params = {
        "client_id": settings.entra_client_id,
        "response_type": "code",
        "redirect_uri": settings.entra_redirect_uri,
        "response_mode": "query",
        "scope": "openid profile email",
        "state": state,
        "nonce": nonce,
        "code_challenge": challenge,
        "code_challenge_method": "S256",
    }
    return RedirectResponse(
        url=f"{_authority(settings)}/oauth2/v2.0/authorize?{urllib.parse.urlencode(params)}",
        status_code=302,
    )


@router.get("/auth/callback")
async def auth_callback(
    request: Request, code: str | None = None, state: str | None = None, error: str | None = None
) -> RedirectResponse:
    """Entra OIDC callback: verify state, exchange the code, validate the ID token, JIT-provision,
    establish a real session. Any failure returns to /signin (no IdP error strings reflected)."""
    settings = get_settings()
    oidc = request.session.pop("oidc", None)
    if error or not code or not state or not oidc or state != oidc.get("state"):
        return RedirectResponse(url=f"{settings.app_base_url}/signin?error=entra_failed", status_code=302)

    try:
        async with httpx.AsyncClient(timeout=10) as client:
            resp = await client.post(
                f"{_authority(settings)}/oauth2/v2.0/token",
                data={
                    "client_id": settings.entra_client_id,
                    "client_secret": settings.entra_client_secret,
                    "grant_type": "authorization_code",
                    "code": code,
                    "redirect_uri": settings.entra_redirect_uri,
                    "code_verifier": oidc["verifier"],
                    "scope": "openid profile email",
                },
            )
        if resp.status_code != 200:
            return RedirectResponse(url=f"{settings.app_base_url}/signin?error=entra_failed", status_code=302)
        claims = _validate_id_token(resp.json()["id_token"], settings, oidc["nonce"])
    except Exception:  # noqa: BLE001 — any failure → back to /signin, never leak details
        return RedirectResponse(url=f"{settings.app_base_url}/signin?error=entra_failed", status_code=302)

    oid = claims["oid"]
    tid = claims.get("tid", settings.entra_tenant_id)
    name = claims.get("name") or claims.get("preferred_username") or "User"
    email = claims.get("email") or claims.get("preferred_username")
    async with request.app.state.pool.connection() as conn:
        actor_id = await jit_provision(
            conn, tenant_id=tid, microsoft_oid=oid, display_name=name, email=email,
            upn=claims.get("preferred_username"),
        )
        if settings.env == "local":  # dev-only: make a fresh Entra user usable immediately
            await _grant_dev_roles_if_empty(conn, actor_id, oid, settings)
    request.session.update(actor_id=actor_id, tenant_id=tid, oid=oid, display_name=name, email=email)
    request.session.pop("logged_out", None)
    return RedirectResponse(url=f"{settings.app_base_url}{oidc['next']}", status_code=302)


def _validate_id_token(token: str, settings: Settings, nonce: str) -> dict:
    """Validate the Entra ID token: RS256 signature (via JWKS), issuer, audience, expiry, and nonce."""
    jwks_url = f"{_authority(settings)}/discovery/v2.0/keys"
    if jwks_url not in _jwk_clients:
        _jwk_clients[jwks_url] = PyJWKClient(jwks_url)
    signing_key = _jwk_clients[jwks_url].get_signing_key_from_jwt(token)
    claims = jwt.decode(
        token, signing_key.key, algorithms=["RS256"],
        audience=settings.entra_client_id,
        issuer=f"{_authority(settings)}/v2.0",
        options={"require": ["exp", "iat", "aud", "iss"]},
    )
    if claims.get("nonce") != nonce:
        raise jwt.InvalidTokenError("nonce mismatch")
    return claims


async def _grant_dev_roles_if_empty(conn, actor_id: str, oid: str, settings: Settings) -> None:
    """LOCAL DEV ONLY (caller-guarded): grant a fresh Entra user a default role set so the app is
    usable. The configured admin gets the admin set; everyone else gets `viewer`. No-op once the
    user holds any role."""
    existing = {r["role_code"] async for r in queries.get_platform_roles(conn, actor_id=actor_id)}
    if existing:
        return
    roles = ADMIN_LOGIN_ROLES if oid == settings.entra_admin_object_id else DEFAULT_LOGIN_ROLES
    for role in roles:
        await queries.grant_platform_role(conn, actor_id=actor_id, role_code=role, granted_by=actor_id)


# ── mock + roles + logout ─────────────────────────────────────────────────────

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
            conn, tenant_id=settings.mock_tenant_id, microsoft_oid=oid,
            display_name=display, email=settings.mock_email, upn=None,
        )
    request.session.update(
        mock_actor_id=actor_id, mock_oid=oid, mock_roles=roles, mock_display_name=display
    )
    request.session.pop("logged_out", None)
    return {"ok": True, "roles": roles}


@router.post("/auth/logout")
async def auth_logout(request: Request) -> dict[str, bool]:
    """Sign-out: clear the session and mark it logged_out so /me reports unauthenticated."""
    request.session.clear()
    request.session["logged_out"] = True
    return {"ok": True}
