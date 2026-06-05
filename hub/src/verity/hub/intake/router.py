"""Intake HTTP routes: create/read intakes, classify, audited status, requirements.
(Application onboarding moved to verity.hub.application — Slice-2 supersedes the thin create.)

Every route is action-gated and fail-closed — the `require_action(...)` dependency resolves the
AuthContext and denies (403) before the handler runs (user-authentication.md). Reads use `view`.
A pooled connection is provided per request; psycopg commits the transaction when the request
completes cleanly and rolls back on any raised error (so a mapped 4xx never half-writes).
"""
from __future__ import annotations

from uuid import UUID

from fastapi import APIRouter, Depends, HTTPException, Request
from psycopg import AsyncConnection
from psycopg.errors import ForeignKeyViolation

from verity.hub.auth.dependencies import require_action
from verity.hub.auth.models import AuthContext
from verity.hub.db import queries
from verity.hub.intake import service
from verity.hub.intake.models import (
    Intake,
    IntakeClassify,
    IntakeCreate,
    IntakeStatusChange,
    Requirement,
    RequirementCreate,
)

router = APIRouter(tags=["intake"])

# Map the intake reference FKs to the offending request field (D-INT-7: a bad reference code
# surfaces as 400 naming the field, not a 500).
_FK_FIELD: dict[str, str] = {
    "fk_intake_risk_tier": "ai_risk_tier_code",
    "fk_intake_naic": "naic_materiality_code",
    "fk_intake_materiality": "materiality_tier_code",
    "fk_intake_status": "to_status_code",
    "fk_intake_requirement_kind": "requirement_kind_code",
}


def _bad_code(exc: ForeignKeyViolation) -> HTTPException:
    field = _FK_FIELD.get(getattr(exc.diag, "constraint_name", "") or "", "reference code")
    return HTTPException(400, f"invalid {field}")


async def get_conn(request: Request):
    """Yield a pooled async connection; psycopg commits on clean exit, rolls back on error."""
    async with request.app.state.pool.connection() as conn:
        yield conn


@router.post("/applications/{application_id}/intakes", status_code=201, response_model=Intake)
async def create_intake(
    application_id: UUID,
    body: IntakeCreate,
    conn: AsyncConnection = Depends(get_conn),
    ctx: AuthContext = Depends(require_action("create_intake")),
) -> Intake:
    gate = await queries.get_application_gate(conn, application_id=application_id)
    if gate is None:
        raise HTTPException(404, "application not found")
    if gate["application_status_code"] != "active":  # FR-IN-015: only an active app owns intakes
        raise HTTPException(409, "application is not active (onboarding not approved)")
    return await service.create_intake(conn, application_id, body, ctx)


@router.get("/applications/{application_id}/intakes", response_model=list[Intake])
async def list_intakes(
    application_id: UUID,
    conn: AsyncConnection = Depends(get_conn),
    ctx: AuthContext = Depends(require_action("view")),
) -> list[Intake]:
    return await service.list_intakes_by_application(conn, application_id)


@router.get("/intakes/{intake_id}", response_model=Intake)
async def get_intake(
    intake_id: UUID,
    conn: AsyncConnection = Depends(get_conn),
    ctx: AuthContext = Depends(require_action("view")),
) -> Intake:
    intake = await service.get_intake(conn, intake_id)
    if intake is None:
        raise HTTPException(404, "intake not found")
    return intake


@router.post("/intakes/{intake_id}/classification", response_model=Intake)
async def classify_intake(
    intake_id: UUID,
    body: IntakeClassify,
    conn: AsyncConnection = Depends(get_conn),
    ctx: AuthContext = Depends(require_action("reclassify_risk")),
) -> Intake:
    try:
        intake = await service.classify_intake(conn, intake_id, body, ctx)
    except ForeignKeyViolation as exc:
        raise _bad_code(exc) from exc
    if intake is None:
        raise HTTPException(404, "intake not found")
    return intake


@router.post("/intakes/{intake_id}/status", response_model=Intake)
async def change_status(
    intake_id: UUID,
    body: IntakeStatusChange,
    conn: AsyncConnection = Depends(get_conn),
    ctx: AuthContext = Depends(require_action("triage_intake")),
) -> Intake:
    try:
        intake = await service.change_status(conn, intake_id, body, ctx)
    except ForeignKeyViolation as exc:
        raise _bad_code(exc) from exc
    if intake is None:
        raise HTTPException(404, "intake not found")
    return intake


@router.post("/intakes/{intake_id}/requirements", status_code=201, response_model=Requirement)
async def add_requirement(
    intake_id: UUID,
    req: RequirementCreate,
    conn: AsyncConnection = Depends(get_conn),
    ctx: AuthContext = Depends(require_action("edit_requirement")),
) -> Requirement:
    if await service.get_intake(conn, intake_id) is None:
        raise HTTPException(404, "intake not found")
    try:
        return await service.add_requirement(conn, intake_id, req, ctx)
    except ForeignKeyViolation as exc:
        raise _bad_code(exc) from exc


@router.get("/intakes/{intake_id}/requirements", response_model=list[Requirement])
async def list_requirements(
    intake_id: UUID,
    conn: AsyncConnection = Depends(get_conn),
    ctx: AuthContext = Depends(require_action("view")),
) -> list[Requirement]:
    return await service.list_requirements(conn, intake_id)
