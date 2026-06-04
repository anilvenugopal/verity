"""FastAPI auth dependencies: resolve the principal, and gate routes on actions (fail-closed)."""
from __future__ import annotations

from fastapi import Depends, Request

from verity.hub.config import get_settings
from verity.hub.auth.authenticator import get_authenticator
from verity.hub.auth.events import emit_auth_event
from verity.hub.auth.matrix import acting_role_for, is_action_allowed
from verity.hub.auth.models import AuthContext, AuthError, Principal


def _request_id(request: Request) -> str:
    return request.headers.get("x-request-id", "local-dev")


async def get_principal(request: Request) -> Principal:
    """Resolve the authenticated principal. In mock mode this is the configured synthetic
    principal; in Entra mode it resolves the server-side session (stub)."""
    settings = get_settings()
    auth = get_authenticator(settings)
    principal = await auth.authenticate(request.app.state.pool, request_id=_request_id(request))
    if principal.disabled:  # FR-021: fail closed
        raise AuthError(403, "account_disabled", "account is disabled")
    return principal


def require_action(action_code: str):
    """Dependency factory gating a route on an action code. Fail-closed; emits a denial
    auth_event on refusal (FR-008, FR-024, FR-029)."""

    async def _dep(request: Request, principal: Principal = Depends(get_principal)) -> AuthContext:
        if not is_action_allowed(principal.platform_roles, action_code):
            await emit_auth_event(
                request.app.state.pool,
                event_type="authz_denial",
                outcome="denied",
                actor_id=principal.actor_id,
                action_code=action_code,
                resource=request.url.path,
                request_id=_request_id(request),
            )
            raise AuthError(403, "forbidden", f"action '{action_code}' not permitted")
        return AuthContext(
            principal=principal,
            action=action_code,
            acting_role=acting_role_for(principal.platform_roles, action_code),
        )

    return _dep
