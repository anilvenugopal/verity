"""Intake HTTP routes (US1): onboard application, create/read intakes.

Every route is action-gated and fail-closed — the `require_action(...)` dependency resolves the
AuthContext and denies (403) before the handler runs (user-authentication.md). Reads use `view`.
A pooled connection is provided per request; psycopg commits the transaction when the request
completes cleanly and rolls back on any raised error (so a mapped 4xx never half-writes).
"""
from __future__ import annotations

from uuid import UUID

from fastapi import APIRouter, Depends, HTTPException, Request
from psycopg import AsyncConnection
from psycopg.errors import UniqueViolation

from verity.hub.auth.dependencies import require_action
from verity.hub.auth.models import AuthContext
from verity.hub.intake import service
from verity.hub.intake.models import Application, ApplicationCreate, Intake, IntakeCreate

router = APIRouter(tags=["intake"])


async def get_conn(request: Request):
    """Yield a pooled async connection; psycopg commits on clean exit, rolls back on error."""
    async with request.app.state.pool.connection() as conn:
        yield conn


@router.post("/applications", status_code=201, response_model=Application)
async def onboard_application(
    body: ApplicationCreate,
    conn: AsyncConnection = Depends(get_conn),
    ctx: AuthContext = Depends(require_action("onboard_application")),
) -> Application:
    try:
        return await service.create_application(conn, body, ctx)
    except UniqueViolation as exc:
        raise HTTPException(409, f"application name '{body.name}' already exists") from exc


@router.get("/applications", response_model=list[Application])
async def list_applications(
    conn: AsyncConnection = Depends(get_conn),
    ctx: AuthContext = Depends(require_action("view")),
) -> list[Application]:
    return await service.list_applications(conn)


@router.get("/applications/{application_id}", response_model=Application)
async def get_application(
    application_id: UUID,
    conn: AsyncConnection = Depends(get_conn),
    ctx: AuthContext = Depends(require_action("view")),
) -> Application:
    application = await service.get_application(conn, application_id)
    if application is None:
        raise HTTPException(404, "application not found")
    return application


@router.post("/applications/{application_id}/intakes", status_code=201, response_model=Intake)
async def create_intake(
    application_id: UUID,
    body: IntakeCreate,
    conn: AsyncConnection = Depends(get_conn),
    ctx: AuthContext = Depends(require_action("create_intake")),
) -> Intake:
    if await service.get_application(conn, application_id) is None:
        raise HTTPException(404, "application not found")
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
