"""Approval HTTP routes (US2): read an approval request and record sign-offs.

Generic surface over the approval primitive; resolution dispatches to the owning slice's policy
(onboarding here). Sign-off is gated `signoff` (an approval-capable role); the finer
'required approver for THIS request' check lives in the onboarding resolution (403 if neither an
AI-Governance holder nor the named business owner). A satisfied quorum activates the application.
"""
from __future__ import annotations

from uuid import UUID

from fastapi import APIRouter, Depends, HTTPException, Request
from psycopg import AsyncConnection
from psycopg.errors import ForeignKeyViolation

from verity.hub.application import service as onboarding
from verity.hub.approval.models import ApprovalRequest, Signoff
from verity.hub.auth.dependencies import require_action
from verity.hub.auth.models import AuthContext

router = APIRouter(tags=["approval"])


async def get_conn(request: Request):
    async with request.app.state.pool.connection() as conn:
        yield conn


@router.get("/approvals/{approval_request_id}", response_model=ApprovalRequest)
async def get_approval(
    approval_request_id: UUID,
    conn: AsyncConnection = Depends(get_conn),
    ctx: AuthContext = Depends(require_action("view")),
) -> ApprovalRequest:
    view = await onboarding.get_request_view(conn, approval_request_id)
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
    try:
        view = await onboarding.sign_off(conn, approval_request_id, ctx, body.decision_code, body.comment)
    except onboarding.OnboardingConflict as exc:
        raise HTTPException(409, str(exc)) from exc
    except ForeignKeyViolation as exc:
        raise HTTPException(400, "invalid decision_code") from exc
    if view is None:
        raise HTTPException(404, "approval request not found")
    return view
