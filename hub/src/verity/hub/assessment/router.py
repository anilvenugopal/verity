"""Intake assessment HTTP routes (US1): submit/read the questionnaire + revision history.

Action-gated, fail-closed: PUT is `edit_impact_assessment`, reads are `view`. A pooled connection
is provided per request (commit on clean exit, rollback on a raised error).
"""
from __future__ import annotations

from uuid import UUID

from fastapi import APIRouter, Depends, HTTPException, Request
from psycopg import AsyncConnection

from verity.hub.assessment import service
from verity.hub.assessment.models import AssessmentInput, AssessmentView, RevisionMeta
from verity.hub.auth.dependencies import require_action
from verity.hub.auth.models import AuthContext

router = APIRouter(tags=["assessment"])


async def get_conn(request: Request):
    async with request.app.state.pool.connection() as conn:
        yield conn


@router.put("/intakes/{intake_id}/assessment", response_model=AssessmentView)
async def submit_assessment(
    intake_id: UUID,
    body: AssessmentInput,
    conn: AsyncConnection = Depends(get_conn),
    ctx: AuthContext = Depends(require_action("edit_impact_assessment")),
) -> AssessmentView:
    view = await service.capture(conn, intake_id, body, ctx)
    if view is None:
        raise HTTPException(404, "intake not found")
    return view


@router.get("/intakes/{intake_id}/assessment", response_model=AssessmentView)
async def get_assessment(
    intake_id: UUID,
    conn: AsyncConnection = Depends(get_conn),
    ctx: AuthContext = Depends(require_action("view")),
) -> AssessmentView:
    view = await service.get_current(conn, intake_id)
    if view is None:
        raise HTTPException(404, "no assessment for this intake")
    return view


@router.get("/intakes/{intake_id}/assessment/revisions", response_model=list[RevisionMeta])
async def list_revisions(
    intake_id: UUID,
    conn: AsyncConnection = Depends(get_conn),
    ctx: AuthContext = Depends(require_action("view")),
) -> list[RevisionMeta]:
    return await service.list_revisions(conn, intake_id)
