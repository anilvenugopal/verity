"""Obligation HTTP routes (003 US1): read the resolved obligation set, record evidence, raise + sign
off compliance exceptions, and the tier-cumulative requirement-status acid test. Action-gated; reads
use `view`. The metamodel is the source of truth — status is derived, never a bespoke flag.
"""
from __future__ import annotations

from typing import Literal
from uuid import UUID

from fastapi import APIRouter, Depends, HTTPException, Request
from psycopg import AsyncConnection
from pydantic import BaseModel

from verity.hub.auth.dependencies import require_action
from verity.hub.auth.models import AuthContext, AuthError
from verity.hub.obligation import service
from verity.hub.obligation.models import (
    EvidenceInput,
    ExceptionInput,
    ExceptionView,
    Obligation,
    ObligationSet,
    RequirementStatus,
)

router = APIRouter(tags=["obligation"])


class ExceptionSignoff(BaseModel):
    decision: Literal["approved", "rejected"]


async def get_conn(request: Request):
    async with request.app.state.pool.connection() as conn:
        yield conn


@router.get("/intakes/{intake_id}/obligations", response_model=ObligationSet)
async def get_obligations(intake_id: UUID, conn: AsyncConnection = Depends(get_conn), ctx: AuthContext = Depends(require_action("view"))) -> ObligationSet:
    return await service.get_obligation_set(conn, intake_id)


@router.post("/obligations/{obligation_id}/evidence", response_model=Obligation)
async def record_evidence(obligation_id: UUID, body: EvidenceInput, conn: AsyncConnection = Depends(get_conn), ctx: AuthContext = Depends(require_action("record_evidence"))) -> Obligation:
    try:
        ob = await service.record_evidence(conn, obligation_id, body.control_code, body.note, ctx)
    except ValueError as exc:
        raise HTTPException(400, str(exc)) from exc
    if ob is None:
        raise HTTPException(404, "obligation not found")
    return ob


@router.get("/requirements/{requirement_code}/status", response_model=RequirementStatus)
async def requirement_status(requirement_code: str, intake: UUID, tier: int, conn: AsyncConnection = Depends(get_conn), ctx: AuthContext = Depends(require_action("view"))) -> RequirementStatus:
    return await service.requirement_status(conn, intake, requirement_code, tier)


@router.post("/intakes/{intake_id}/exceptions", response_model=ExceptionView, status_code=201)
async def raise_exception(intake_id: UUID, body: ExceptionInput, conn: AsyncConnection = Depends(get_conn), ctx: AuthContext = Depends(require_action("edit_impact_assessment"))) -> ExceptionView:
    try:
        return await service.raise_exception(conn, intake_id, body, ctx)
    except ValueError as exc:
        raise HTTPException(400, str(exc)) from exc


@router.post("/exceptions/{exception_id}/signoff", response_model=ExceptionView)
async def signoff_exception(exception_id: UUID, body: ExceptionSignoff, conn: AsyncConnection = Depends(get_conn), ctx: AuthContext = Depends(require_action("approve_exception"))) -> ExceptionView:
    try:
        exc = await service.signoff_exception(conn, exception_id, body.decision, ctx)
    except service.ObligationConflict as e:
        raise HTTPException(409, str(e)) from e
    except AuthError as e:
        raise HTTPException(403, e.detail) from e
    if exc is None:
        raise HTTPException(404, "exception not found")
    return exc
