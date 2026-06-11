"""Change-proposal HTTP routes (003 US3): raise a proposal against an approved intake.

Sign-off is handled by the shared `POST /approvals/{id}/signoff` route in approval.router, which
dispatches to this module's service for kind=risk_reclassification/business_change. Only the
`POST /intakes/{id}/change-proposals` and `GET /intakes/{id}/change-proposals` live here.
"""
from __future__ import annotations

from uuid import UUID

from fastapi import APIRouter, Depends, HTTPException, Request
from psycopg import AsyncConnection

from verity.hub.auth.dependencies import require_action
from verity.hub.auth.models import AuthContext
from verity.hub.change_proposal import service as cp_service
from verity.hub.change_proposal.models import ChangeProposalInput, ChangeProposalView

router = APIRouter(tags=["change-proposals"])


async def get_conn(request: Request):
    async with request.app.state.pool.connection() as conn:
        yield conn


@router.post("/intakes/{intake_id}/change-proposals", response_model=ChangeProposalView, status_code=201)
async def raise_change_proposal(
    intake_id: UUID,
    body: ChangeProposalInput,
    conn: AsyncConnection = Depends(get_conn),
    ctx: AuthContext = Depends(require_action("reclassify_risk")),
) -> ChangeProposalView:
    """Raise a risk_reclassification or business_change proposal against an approved intake."""
    try:
        return await cp_service.open_proposal(conn, intake_id, body.kind_code, body.asset_ids, ctx)
    except ValueError as exc:
        raise HTTPException(400, str(exc)) from exc
    except cp_service.ChangeProposalConflict as exc:
        raise HTTPException(409, str(exc)) from exc


@router.get("/intakes/{intake_id}/change-proposals", response_model=list[ChangeProposalView])
async def list_change_proposals(
    intake_id: UUID,
    conn: AsyncConnection = Depends(get_conn),
    ctx: AuthContext = Depends(require_action("view")),
) -> list[ChangeProposalView]:
    """List all change proposals (any status) for an intake, newest first."""
    return await cp_service.list_intake_proposals(conn, intake_id)
