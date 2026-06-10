"""Intake approval HTTP routes (Slice 4): submit an intake for approval.

The sign-off + read routes are the shared `/approvals/{id}` surface (approval/router.py), which
dispatches by `request_kind_code` to this service for `kind=intake`. Submit is gated `edit_intake`.
"""
from __future__ import annotations

from uuid import UUID

from fastapi import APIRouter, Depends, HTTPException, Request
from psycopg import AsyncConnection

from verity.hub.approval.models import ApprovalRequest, SubmitForApproval
from verity.hub.auth.dependencies import require_action
from verity.hub.auth.models import AuthContext
from verity.hub.intake_approval import service

router = APIRouter(tags=["intake-approval"])


async def get_conn(request: Request):
    async with request.app.state.pool.connection() as conn:
        yield conn


@router.get("/intakes/{intake_id}/approval", response_model=ApprovalRequest)
async def get_intake_approval(
    intake_id: UUID,
    conn: AsyncConnection = Depends(get_conn),
    ctx: AuthContext = Depends(require_action("view")),
) -> ApprovalRequest:
    """The intake's latest kind=intake approval view (mirrors GET /applications/{id}/approval).
    404 when the intake was never submitted — the detail page treats that as 'not submitted'."""
    view = await service.get_intake_approval_view(conn, intake_id)
    if view is None:
        raise HTTPException(404, "no approval for this intake")
    return view


@router.post("/intakes/{intake_id}/submit", status_code=201, response_model=ApprovalRequest)
async def submit_intake(
    intake_id: UUID,
    body: SubmitForApproval,
    conn: AsyncConnection = Depends(get_conn),
    ctx: AuthContext = Depends(require_action("edit_intake")),
) -> ApprovalRequest:
    try:
        view = await service.submit_for_approval(conn, intake_id, ctx)
    except service.IntakeApprovalConflict as exc:
        raise HTTPException(409, str(exc)) from exc
    except ValueError as exc:  # no tier yet
        raise HTTPException(400, str(exc)) from exc
    if view is None:
        raise HTTPException(404, "intake not found")
    return view
