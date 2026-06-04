"""Intake service: the thin layer between the router and the raw SQL (ADR-0012).

Each write binds attribution (`created_by_actor_id`, `created_role_code`) from the AuthContext the
gate produced — the actor and the capacity they acted in (D6). The role is server-resolved, never
read from the request body (FR-018). dict_row rows map straight onto the boundary models.
"""
from __future__ import annotations

from uuid import UUID

from psycopg import AsyncConnection

from verity.hub.auth.models import AuthContext
from verity.hub.db import queries
from verity.hub.intake.models import (
    Application,
    ApplicationCreate,
    Intake,
    IntakeCreate,
)


async def create_application(conn: AsyncConnection, body: ApplicationCreate, ctx: AuthContext) -> Application:
    row = await queries.create_application(
        conn,
        name=body.name,
        description=body.description,
        created_by_actor_id=ctx.principal.actor_id,
        created_role_code=ctx.acting_role,
    )
    return Application(**row)


async def get_application(conn: AsyncConnection, application_id: UUID) -> Application | None:
    row = await queries.get_application(conn, application_id=application_id)
    return Application(**row) if row else None


async def list_applications(conn: AsyncConnection) -> list[Application]:
    return [Application(**r) async for r in queries.list_applications(conn)]


async def create_intake(
    conn: AsyncConnection, application_id: UUID, body: IntakeCreate, ctx: AuthContext
) -> Intake:
    row = await queries.create_intake(
        conn,
        application_id=application_id,
        title=body.title,
        description=body.description,
        created_by_actor_id=ctx.principal.actor_id,
        created_role_code=ctx.acting_role,
    )
    return Intake(**row)


async def get_intake(conn: AsyncConnection, intake_id: UUID) -> Intake | None:
    row = await queries.get_intake(conn, intake_id=intake_id)
    return Intake(**row) if row else None


async def list_intakes_by_application(conn: AsyncConnection, application_id: UUID) -> list[Intake]:
    return [
        Intake(**r) async for r in queries.list_intakes_by_application(conn, application_id=application_id)
    ]
