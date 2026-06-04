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
    IntakeClassify,
    IntakeCreate,
    IntakeStatusChange,
    Requirement,
    RequirementCreate,
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


async def classify_intake(
    conn: AsyncConnection, intake_id: UUID, body: IntakeClassify, ctx: AuthContext
) -> Intake | None:
    """Set/refresh the intake's risk tier + materiality (US2). The gate (reclassify_risk) has
    already authorized `ctx`; codes are validated by their reference FKs in the UPDATE. Returns
    None if the intake does not exist."""
    row = await queries.classify_intake(
        conn,
        intake_id=intake_id,
        ai_risk_tier_code=body.ai_risk_tier_code,
        naic_materiality_code=body.naic_materiality_code,
        materiality_tier_code=body.materiality_tier_code,
    )
    return Intake(**row) if row else None


async def change_status(
    conn: AsyncConnection, intake_id: UUID, body: IntakeStatusChange, ctx: AuthContext
) -> Intake | None:
    """Move an intake's status and append its audit row in ONE transaction (D-INT-1): the mutable
    status and its append-only history never diverge. Returns None if the intake does not exist.
    An invalid to-code raises a FK violation (rolling the whole txn back) for the router to map to
    400 — so a rejected change writes neither the status nor an audit row."""
    async with conn.transaction():
        current = await queries.get_intake_status(conn, intake_id=intake_id)
        if current is None:
            return None
        row = await queries.update_intake_status(
            conn, intake_id=intake_id, to_status_code=body.to_status_code
        )
        await queries.insert_status_transition(
            conn,
            entity_id=intake_id,
            from_code=current["intake_status_code"],
            to_code=body.to_status_code,
            actor_id=ctx.principal.actor_id,
            acting_role_code=ctx.acting_role,
            reason=body.reason,
        )
    return Intake(**row)


async def add_requirement(
    conn: AsyncConnection, intake_id: UUID, req: RequirementCreate, ctx: AuthContext
) -> Requirement:
    """Add a typed requirement to an intake (US4). embedding is left null (D-INT-6). Attribution
    is server-resolved from the gate's AuthContext (D6)."""
    row = await queries.add_requirement(
        conn,
        intake_id=intake_id,
        requirement_kind_code=req.requirement_kind_code,
        title=req.title,
        body=req.body,
        created_by_actor_id=ctx.principal.actor_id,
        created_role_code=ctx.acting_role,
    )
    return Requirement(**row)


async def list_requirements(conn: AsyncConnection, intake_id: UUID) -> list[Requirement]:
    return [
        Requirement(**r) async for r in queries.list_requirements(conn, intake_id=intake_id)
    ]
