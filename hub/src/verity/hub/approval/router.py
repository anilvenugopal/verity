"""Approval HTTP routes: read an approval request and record sign-offs.

Generic surface over the approval primitive; both routes **dispatch by `request_kind_code`** to the
owning slice's resolution policy: `application_onboarding` → `verity.hub.application.service`,
`intake` → `verity.hub.intake_approval.service`. Sign-off is gated `signoff` (an approval-capable
role); the finer 'required approver for THIS request' check lives in each slice's resolution (403).
"""
from __future__ import annotations

from uuid import UUID

from fastapi import APIRouter, Depends, HTTPException, Request
from psycopg import AsyncConnection
from psycopg.errors import ForeignKeyViolation

from verity.hub.application import service as onboarding
from verity.hub.approval import service as approval_service
from verity.hub.approval.models import ApprovalRequest, AwaitingApproval, Signoff
from verity.hub.auth.dependencies import require_action
from verity.hub.auth.models import AuthContext
from verity.hub.intake_approval import service as intake_approval

router = APIRouter(tags=["approval"])

# Per-kind conflict exceptions to map to 409.
_CONFLICTS = (onboarding.OnboardingConflict, intake_approval.IntakeApprovalConflict)


async def get_conn(request: Request):
    async with request.app.state.pool.connection() as conn:
        yield conn


async def _kind(conn: AsyncConnection, approval_request_id: UUID) -> str | None:
    request = await approval_service.get_request(conn, approval_request_id)
    return request["request_kind_code"] if request else None


@router.get("/approvals/awaiting-me", response_model=list[AwaitingApproval])
async def awaiting_me(
    conn: AsyncConnection = Depends(get_conn),
    ctx: AuthContext = Depends(require_action("view")),
) -> list[AwaitingApproval]:
    """The caller's MY APPROVALS queue: pending onboarding requests they can act on (declared before
    the /{approval_request_id} route so 'awaiting-me' isn't parsed as a UUID)."""
    return await onboarding.awaiting_onboarding_approvals(conn, ctx)


@router.get("/approvals/{approval_request_id}", response_model=ApprovalRequest)
async def get_approval(
    approval_request_id: UUID,
    conn: AsyncConnection = Depends(get_conn),
    ctx: AuthContext = Depends(require_action("view")),
) -> ApprovalRequest:
    kind = await _kind(conn, approval_request_id)
    if kind is None:
        raise HTTPException(404, "approval request not found")
    resolver = intake_approval if kind == "intake" else onboarding
    view = await resolver.get_request_view(conn, approval_request_id)
    if view is None:
        raise HTTPException(404, "approval request not found")
    return view


@router.post("/approvals/{approval_request_id}/signoff", response_model=ApprovalRequest)
async def sign_off(
    approval_request_id: UUID,
    body: Signoff,
    conn: AsyncConnection = Depends(get_conn),
    ctx: AuthContext = Depends(require_action("signoff")),
) -> ApprovalRequest:
    kind = await _kind(conn, approval_request_id)
    if kind is None:
        raise HTTPException(404, "approval request not found")
    resolver = intake_approval if kind == "intake" else onboarding
    try:
        view = await resolver.sign_off(conn, approval_request_id, ctx, body.decision_code, body.comment)
    except _CONFLICTS as exc:
        raise HTTPException(409, str(exc)) from exc
    except ForeignKeyViolation as exc:
        raise HTTPException(400, "invalid decision_code") from exc
    if view is None:
        raise HTTPException(404, "approval request not found")
    return view
