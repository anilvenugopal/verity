"""Registry service (003 US2): the minimal asset primitive (executable + immutable version + lifecycle
advance + champion) and the PROMOTION GATE — advancing a version to a production-reaching stage
(challenger/champion) requires the asset be linked to an approved intake whose obligations are all
satisfied/excepted (research D4). Early stages (draft/candidate/staging) are exempt.
"""
from __future__ import annotations

from uuid import UUID

from psycopg import AsyncConnection
from psycopg.types.json import Json

from verity.hub.auth.models import AuthContext
from verity.hub.db import queries
from verity.hub.obligation import service as obligation_service
from verity.hub.registry.models import Executable, ExecutableVersion, IntakeAssetLink

_GATED = {"challenger", "champion"}  # production-reaching stages
_EARLY = {None, "draft", "candidate"}  # link-eligible stages


class RegistryGateBlock(Exception):
    """409 — promotion blocked (not_linked / intake_not_approved / outstanding_obligation)."""

    def __init__(self, reason: str, requirement_code: str | None = None) -> None:
        self.reason = reason
        self.requirement_code = requirement_code
        detail = f"promotion blocked: {reason}" + (f" ({requirement_code})" if requirement_code else "")
        super().__init__(detail)


async def create_executable(conn: AsyncConnection, name: str, kind_code: str, ctx: AuthContext) -> Executable:
    row = await queries.create_executable(conn, kind_code=kind_code, name=name, description=None,
                                          created_by_actor_id=ctx.principal.actor_id, created_role_code=ctx.acting_role)
    return Executable(executable_id=row["executable_id"], kind_code=row["kind_code"], name=row["name"], version_count=0)


async def list_executables(conn: AsyncConnection) -> list[Executable]:
    return [Executable(**r) async for r in queries.list_executables(conn)]


async def list_versions(conn: AsyncConnection, executable_id: UUID) -> list[ExecutableVersion]:
    return [ExecutableVersion(executable_version_id=r["executable_version_id"], executable_id=executable_id,
                              semver=r["semver"], lifecycle_stage=r["lifecycle_state_code"])
            async for r in queries.list_executable_versions(conn, executable_id=executable_id)]


async def create_version(conn: AsyncConnection, executable_id: UUID, ctx: AuthContext) -> ExecutableVersion | None:
    ex = await queries.get_executable(conn, executable_id=executable_id)
    if ex is None:
        return None
    n = (await queries.version_count(conn, executable_id=executable_id))["n"]
    semver = f"0.{n + 1}.0"
    async with conn.transaction():
        v = await queries.create_version(conn, executable_id=executable_id, kind_code=ex["kind_code"], semver=semver,
                                         created_by_actor_id=ctx.principal.actor_id, created_role_code=ctx.acting_role)
        await queries.insert_lifecycle_event(conn, version_id=v["executable_version_id"], from_state=None, to_state="draft",
                                             approval_request_id=None, rationale="created", detail=Json({"event": "initial draft"}),
                                             actor_id=ctx.principal.actor_id, acting_role_code=ctx.acting_role)
    return ExecutableVersion(executable_version_id=v["executable_version_id"], executable_id=executable_id, semver=semver, lifecycle_stage="draft")


async def advance_lifecycle(conn: AsyncConnection, version_id: UUID, to_stage: str, ctx: AuthContext) -> ExecutableVersion | None:
    """None => the version does not exist (404); raises RegistryGateBlock (409) when the gate denies."""
    v = await queries.get_version(conn, version_id=version_id)
    if v is None:
        return None
    cur = await queries.current_state(conn, version_id=version_id)
    current = cur["lifecycle_state_code"] if cur else None
    if to_stage in _GATED:
        link = await queries.link_for_executable(conn, executable_id=v["executable_id"])
        if link is None:
            raise RegistryGateBlock("not_linked")
        if link["intake_status_code"] != "approved":
            raise RegistryGateBlock("intake_not_approved")
        oblig = await obligation_service.get_obligation_set(conn, link["intake_id"])
        if not oblig.rollup.all_resolved:
            outstanding = next((o.requirement_code for o in oblig.obligations if o.status == "outstanding"), None)
            raise RegistryGateBlock("outstanding_obligation", outstanding)
    async with conn.transaction():
        ev = await queries.insert_lifecycle_event(conn, version_id=version_id, from_state=current, to_state=to_stage,
                                                  approval_request_id=None, rationale="lifecycle advance", detail=Json({"from": current, "to": to_stage}),
                                                  actor_id=ctx.principal.actor_id, acting_role_code=ctx.acting_role)
        if to_stage == "champion":
            await queries.insert_champion(conn, version_id=version_id, lifecycle_event_id=ev["lifecycle_event_id"],
                                          reason="promoted", actor_id=ctx.principal.actor_id, acting_role_code=ctx.acting_role)
    return ExecutableVersion(executable_version_id=version_id, executable_id=v["executable_id"], semver=v["semver"], lifecycle_stage=to_stage)


async def link(conn: AsyncConnection, intake_id: UUID, executable_id: UUID, requirement_id: UUID | None, ctx: AuthContext) -> None:
    """Link an asset to an intake requirement — at most one intake per asset, early-stage only (FR-008)."""
    if await queries.get_executable(conn, executable_id=executable_id) is None:
        raise ValueError("unknown asset")
    if await queries.link_for_executable(conn, executable_id=executable_id) is not None:
        raise ValueError("asset is already linked to an intake")
    top = await queries.asset_top_stage(conn, executable_id=executable_id)
    if top is not None and top["top_stage"] not in _EARLY:
        raise ValueError("asset is past the early lifecycle stage and can no longer be linked")
    async with conn.transaction():
        await queries.insert_link(conn, intake_id=intake_id, intake_requirement_id=requirement_id, executable_id=executable_id,
                                  created_by_actor_id=ctx.principal.actor_id, created_role_code=ctx.acting_role)


async def unlink(conn: AsyncConnection, link_id: UUID, ctx: AuthContext) -> None:
    async with conn.transaction():
        await queries.delete_link(conn, link_id=link_id)


async def list_intake_links(conn: AsyncConnection, intake_id: UUID) -> list[IntakeAssetLink]:
    return [IntakeAssetLink(**r) async for r in queries.list_intake_links(conn, intake_id=intake_id)]
