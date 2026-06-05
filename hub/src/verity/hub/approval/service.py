"""The minimal, reusable approval primitive (US2): open a request, record sign-offs, read it back.

Generic over kind/target — it knows nothing about onboarding/intake/deployment policy. The
per-kind quorum and any side effects on resolution (e.g. activating an application) live in the
calling slice's service (for onboarding: verity.hub.application.service). D-ONB-1.
"""
from __future__ import annotations

from uuid import UUID

from psycopg import AsyncConnection

from verity.hub.approval.models import ApprovalRequest, SignoffRecord
from verity.hub.db import queries


async def open_request(
    conn: AsyncConnection, *, request_kind_code: str,
    opened_by_actor_id: str, opened_role_code: str,
    target_intake_id: UUID | None = None, target_application_id: UUID | None = None,
) -> dict:
    """Open a generic approval request — bind exactly one target (intake XOR application)."""
    return await queries.open_request(
        conn,
        request_kind_code=request_kind_code,
        target_intake_id=target_intake_id,
        target_application_id=target_application_id,
        opened_by_actor_id=opened_by_actor_id,
        opened_role_code=opened_role_code,
    )


async def get_request(conn: AsyncConnection, approval_request_id: UUID) -> dict | None:
    return await queries.get_request(conn, approval_request_id=approval_request_id)


async def list_signoffs(conn: AsyncConnection, approval_request_id: UUID) -> list[dict]:
    return [r async for r in queries.list_signoffs(conn, approval_request_id=approval_request_id)]


async def insert_signoff(
    conn: AsyncConnection, *, approval_request_id: UUID, approver_actor_id: str,
    signed_as_role_code: str, decision_code: str, comment: str | None,
) -> None:
    await queries.insert_signoff(
        conn, approval_request_id=approval_request_id, approver_actor_id=approver_actor_id,
        signed_as_role_code=signed_as_role_code, decision_code=decision_code, comment=comment,
    )


async def set_request_status(conn: AsyncConnection, approval_request_id: UUID, status_code: str) -> None:
    await queries.set_request_status(conn, approval_request_id=approval_request_id, status_code=status_code)


def build_view(request_row: dict, signoffs: list[dict], required_roles: list[str]) -> ApprovalRequest:
    return ApprovalRequest(
        **request_row,
        required_roles=required_roles,
        signoffs=[SignoffRecord(**s) for s in signoffs],
    )
