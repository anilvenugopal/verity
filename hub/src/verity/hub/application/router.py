"""Application onboarding HTTP routes (US1): propose + read.

Action-gated, fail-closed (user-authentication.md). Propose creates the application `pending`;
submit-for-approval and the sign-off flow that activates it are US2. A pooled connection is
provided per request (psycopg commits on clean exit, rolls back on a raised error).
"""
from __future__ import annotations

from uuid import UUID

from fastapi import APIRouter, Depends, HTTPException, Request
from psycopg import AsyncConnection
from psycopg.errors import ForeignKeyViolation, UniqueViolation

from verity.hub.application import service
from verity.hub.application.models import Application, ApplicationPropose, LifecycleChange
from verity.hub.approval.models import ApprovalRequest, SubmitForApproval
from verity.hub.auth.dependencies import require_action
from verity.hub.auth.models import AuthContext

router = APIRouter(tags=["application"])

# Map the application/perimeter FKs to the offending request field (D-INT-7 style: bad reference
# code -> 400 naming the field, not 500).
_FK_FIELD: dict[str, str] = {
    "fk_application_data_classification": "data_classification_code",
    "fk_application_lob": "line_of_business_code",
    "fk_application_business_owner": "business_owner_actor_id",
    "fk_app_framework_framework": "regulatory_framework_codes",
    "fk_app_domain_domain": "governance_domain_codes",
    "fk_app_jurisdiction_jurisdiction": "jurisdiction_codes",
    "fk_actor_app_grant_role": "initial_app_team.app_team_role_code",
    "fk_actor_app_grant_actor": "initial_app_team.actor_id",
}


async def get_conn(request: Request):
    async with request.app.state.pool.connection() as conn:
        yield conn


@router.post("/applications", status_code=201, response_model=Application)
async def propose_application(
    body: ApplicationPropose,
    conn: AsyncConnection = Depends(get_conn),
    ctx: AuthContext = Depends(require_action("onboard_application")),
) -> Application:
    try:
        return await service.propose(conn, body, ctx)
    except UniqueViolation as exc:
        raise HTTPException(409, f"application code '{body.code}' already exists") from exc
    except ForeignKeyViolation as exc:
        field = _FK_FIELD.get(getattr(exc.diag, "constraint_name", "") or "", "reference code")
        raise HTTPException(400, f"invalid {field}") from exc
    except ValueError as exc:
        raise HTTPException(400, str(exc)) from exc


@router.put("/applications/{application_id}", response_model=Application)
async def update_application(
    application_id: UUID,
    body: ApplicationPropose,
    conn: AsyncConnection = Depends(get_conn),
    ctx: AuthContext = Depends(require_action("onboard_application")),
) -> Application:
    """Edit a pending application (pre-activation remediation, e.g. after a rejection)."""
    try:
        updated = await service.update(conn, application_id, body, ctx)
    except service.OnboardingConflict as exc:
        raise HTTPException(409, str(exc)) from exc
    except UniqueViolation as exc:
        raise HTTPException(409, f"application code '{body.code}' already exists") from exc
    except ForeignKeyViolation as exc:
        field = _FK_FIELD.get(getattr(exc.diag, "constraint_name", "") or "", "reference code")
        raise HTTPException(400, f"invalid {field}") from exc
    except ValueError as exc:
        raise HTTPException(400, str(exc)) from exc
    if updated is None:
        raise HTTPException(404, "application not found")
    return updated


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


@router.post("/applications/{application_id}/withdraw", response_model=Application)
async def withdraw_application(
    application_id: UUID,
    conn: AsyncConnection = Depends(get_conn),
    ctx: AuthContext = Depends(require_action("onboard_application")),
) -> Application:
    """Cancel the application's pending approval (the requester withdrawing their submission)."""
    try:
        app = await service.withdraw(conn, application_id, ctx)
    except service.OnboardingConflict as exc:
        raise HTTPException(409, str(exc)) from exc
    if app is None:
        raise HTTPException(404, "application not found")
    return app


@router.delete("/applications/{application_id}", status_code=204)
async def delete_application(
    application_id: UUID,
    conn: AsyncConnection = Depends(get_conn),
    ctx: AuthContext = Depends(require_action("delete_application")),
) -> None:
    """Hard-delete a pending application + its dependents (security-only, API maintenance; no UI)."""
    try:
        deleted = await service.delete_application(conn, application_id)
    except service.OnboardingConflict as exc:
        raise HTTPException(409, str(exc)) from exc
    if deleted is None:
        raise HTTPException(404, "application not found")


@router.get("/applications/{application_id}/approval", response_model=ApprovalRequest)
async def get_application_approval(
    application_id: UUID,
    conn: AsyncConnection = Depends(get_conn),
    ctx: AuthContext = Depends(require_action("view")),
) -> ApprovalRequest:
    view = await service.get_application_approval_view(conn, application_id)
    if view is None:
        raise HTTPException(404, "no approval for this application")
    return view


@router.post("/applications/{application_id}/submit", status_code=201, response_model=ApprovalRequest)
async def submit_for_approval(
    application_id: UUID,
    body: SubmitForApproval,
    conn: AsyncConnection = Depends(get_conn),
    ctx: AuthContext = Depends(require_action("onboard_application")),
) -> ApprovalRequest:
    try:
        request = await service.submit_for_approval(conn, application_id, ctx)
    except service.OnboardingConflict as exc:
        raise HTTPException(409, str(exc)) from exc
    if request is None:
        raise HTTPException(404, "application not found")
    return request


@router.post("/applications/{application_id}/lifecycle", response_model=Application)
async def change_lifecycle(
    application_id: UUID,
    body: LifecycleChange,
    conn: AsyncConnection = Depends(get_conn),
    ctx: AuthContext = Depends(require_action("onboard_application")),
) -> Application:
    try:
        application = await service.change_status(conn, application_id, body.to_status_code, ctx)
    except ValueError as exc:
        raise HTTPException(400, str(exc)) from exc
    except service.OnboardingConflict as exc:
        raise HTTPException(409, str(exc)) from exc
    if application is None:
        raise HTTPException(404, "application not found")
    return application
