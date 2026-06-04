"""Authenticators behind one interface: a fully-implemented fail-closed mock path (FR-030)
and the Entra OIDC stub (FR-001..FR-004a, implemented in a follow-up)."""
from __future__ import annotations

from typing import Protocol

from ..config import Settings
from ..db import queries
from .events import emit_auth_event
from .models import Principal
from .provisioning import jit_provision


class Authenticator(Protocol):
    async def authenticate(self, pool, request_id: str) -> Principal: ...


class MockAuthenticator:
    """A config-sourced synthetic principal that flows through the SAME provisioning,
    role-resolution, and action-gate paths as a real principal (FR-030). Local-dev only;
    the env guardrail is enforced at startup (config.validate_startup)."""

    def __init__(self, settings: Settings) -> None:
        self.s = settings

    async def authenticate(self, pool, request_id: str) -> Principal:
        s = self.s
        async with pool.connection() as conn:
            actor_id = await jit_provision(
                conn,
                tenant_id=s.mock_tenant_id,
                microsoft_oid=s.mock_microsoft_oid,
                display_name=s.mock_display_name,
                email=s.mock_email,
                upn=None,
            )
            # dev seed: ensure configured roles exist as grants so resolution uses the real path
            for role in s.mock_roles:
                if not await queries.has_role_grant(conn, actor_id=actor_id, role_code=role):
                    await queries.grant_platform_role(
                        conn, actor_id=actor_id, role_code=role, granted_by=actor_id
                    )
            # apsycopg select-many yields an async generator -> iterate with async for
            roles = {r[0] async for r in queries.get_platform_roles(conn, actor_id=actor_id)}
            _, epoch, disabled_at = await queries.get_account_state(
                conn, tenant_id=s.mock_tenant_id, microsoft_oid=s.mock_microsoft_oid
            )
        await emit_auth_event(
            pool, event_type="login", outcome="success", reason_code="mock_auth",
            actor_id=actor_id, request_id=request_id,
        )
        return Principal(
            actor_id=actor_id, tenant_id=s.mock_tenant_id, microsoft_oid=s.mock_microsoft_oid,
            display_name=s.mock_display_name, email=s.mock_email,
            platform_roles=roles, session_epoch=epoch, disabled=disabled_at is not None,
        )


class EntraAuthenticator:
    """Entra OIDC Authorization Code + PKCE (FR-001..FR-004a) — stub.

    The full flow (server-side state/nonce/PKCE mint, code exchange, explicit RS256/iss/aud/
    tid/nonce validation, JWKS hardening, JIT provisioning, opaque server-side session) is
    implemented in a follow-up against user-authentication.md; the interface is fixed here.
    """

    def __init__(self, settings: Settings) -> None:
        self.s = settings

    async def authenticate(self, pool, request_id: str) -> Principal:
        raise NotImplementedError(
            "Entra OIDC flow not yet implemented (user-authentication.md FR-001..FR-004a)"
        )


def get_authenticator(settings: Settings) -> Authenticator:
    return MockAuthenticator(settings) if settings.auth_mode == "mock" else EntraAuthenticator(settings)
