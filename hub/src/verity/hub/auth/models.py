"""Auth boundary models (Pydantic v2) and the AuthError."""
from __future__ import annotations

from pydantic import BaseModel, Field


class Principal(BaseModel):
    """The authenticated principal — resolved from the DB, never from token claims (FR-007).

    Identity is the immutable (tenant_id, microsoft_oid); roles come from current_actor_role.
    """

    actor_id: str
    tenant_id: str
    microsoft_oid: str
    display_name: str
    email: str | None = None
    platform_roles: set[str] = Field(default_factory=set)
    session_epoch: int = 0
    disabled: bool = False


class AuthError(Exception):
    """Carries an HTTP status (401 unauthenticated / 403 denied) and a stable, non-leaking code."""

    def __init__(self, status_code: int, code: str, detail: str) -> None:
        self.status_code = status_code
        self.code = code
        self.detail = detail
        super().__init__(detail)
