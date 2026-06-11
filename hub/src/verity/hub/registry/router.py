"""Registry HTTP routes (003 US2): the minimal asset primitive, intake↔asset linking, and the
promotion gate (enforced inside lifecycle advance → 409 when blocked). Action-gated."""
from __future__ import annotations

from uuid import UUID

from fastapi import APIRouter, Depends, HTTPException, Request
from psycopg import AsyncConnection

from verity.hub.auth.dependencies import require_action
from verity.hub.auth.models import AuthContext
from verity.hub.registry import service
from verity.hub.registry.models import (
    CreateExecutable,
    Executable,
    ExecutableVersion,
    IntakeAssetLink,
    LifecycleAdvance,
    LinkInput,
)

router = APIRouter(tags=["registry"])


async def get_conn(request: Request):
    async with request.app.state.pool.connection() as conn:
        yield conn


@router.get("/executables", response_model=list[Executable])
async def list_executables(conn: AsyncConnection = Depends(get_conn), ctx: AuthContext = Depends(require_action("view"))) -> list[Executable]:
    return await service.list_executables(conn)


@router.post("/executables", response_model=Executable, status_code=201)
async def create_executable(body: CreateExecutable, conn: AsyncConnection = Depends(get_conn), ctx: AuthContext = Depends(require_action("author_registry"))) -> Executable:
    return await service.create_executable(conn, body.name, body.kind_code, ctx)


@router.get("/executables/{executable_id}/versions", response_model=list[ExecutableVersion])
async def list_versions(executable_id: UUID, conn: AsyncConnection = Depends(get_conn), ctx: AuthContext = Depends(require_action("view"))) -> list[ExecutableVersion]:
    return await service.list_versions(conn, executable_id)


@router.post("/executables/{executable_id}/versions", response_model=ExecutableVersion, status_code=201)
async def create_version(executable_id: UUID, conn: AsyncConnection = Depends(get_conn), ctx: AuthContext = Depends(require_action("author_registry"))) -> ExecutableVersion:
    v = await service.create_version(conn, executable_id, ctx)
    if v is None:
        raise HTTPException(404, "executable not found")
    return v


@router.post("/versions/{version_id}/lifecycle", response_model=ExecutableVersion)
async def advance_lifecycle(version_id: UUID, body: LifecycleAdvance, conn: AsyncConnection = Depends(get_conn), ctx: AuthContext = Depends(require_action("promote_registry"))) -> ExecutableVersion:
    try:
        v = await service.advance_lifecycle(conn, version_id, body.to_stage, ctx)
    except service.RegistryGateBlock as gb:
        raise HTTPException(409, str(gb)) from gb
    if v is None:
        raise HTTPException(404, "version not found")
    return v


@router.post("/intakes/{intake_id}/links", status_code=201)
async def link_asset(intake_id: UUID, body: LinkInput, conn: AsyncConnection = Depends(get_conn), ctx: AuthContext = Depends(require_action("link_asset"))) -> dict:
    try:
        await service.link(conn, intake_id, body.executable_id, body.intake_requirement_id, ctx)
    except ValueError as exc:
        raise HTTPException(409, str(exc)) from exc
    return {"ok": True}


@router.delete("/links/{link_id}", status_code=204)
async def unlink_asset(link_id: UUID, conn: AsyncConnection = Depends(get_conn), ctx: AuthContext = Depends(require_action("link_asset"))) -> None:
    await service.unlink(conn, link_id, ctx)


@router.get("/intakes/{intake_id}/links", response_model=list[IntakeAssetLink])
async def list_links(intake_id: UUID, conn: AsyncConnection = Depends(get_conn), ctx: AuthContext = Depends(require_action("view"))) -> list[IntakeAssetLink]:
    return await service.list_intake_links(conn, intake_id)
