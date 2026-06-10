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
    IntakeListItem,
    IntakeStatusChange,
    Requirement,
    RequirementCreate,
    RequirementUpdate,
)


class IntakeConflict(Exception):
    """A 409 — the intake is locked (approved/in_build/live/retired) and no longer revisable, or
    there is no open approval to withdraw. Mirrors application.service.OnboardingConflict."""


# Revisable (editable / withdrawable / deletable) = the three pre-decision authoring states
# {proposed, in_review, impact_assessment}; everything else is locked. The remediation loop still
# works because a quorum *rejection* leaves the intake at in_review (the approval *request* reads
# 'rejected', the intake does not) — exactly like a rejected application stays 'pending'. An explicit
# `rejected`/`retired` is a terminal governance kill (kept for audit), and `approved`/`in_build`/`live`
# are post-decision — all locked.
_LOCKED_STATUSES = frozenset({"approved", "rejected", "retired", "in_build", "live"})


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


async def list_all_intakes(conn: AsyncConnection) -> list[IntakeListItem]:
    """Every intake (newest first) for the top-level Use Cases list, each carrying its application's
    name + created_by. Role gating is the route's require_action("view")."""
    return [IntakeListItem(**r) async for r in queries.list_all_intakes(conn)]


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


async def update_intake(
    conn: AsyncConnection, intake_id: UUID, body: IntakeCreate, ctx: AuthContext
) -> Intake | None:
    """Edit a still-revisable intake's title/description in place (pre-activation remediation, e.g.
    after a rejection). None => 404; raises IntakeConflict (409) if the intake is locked. Authorization
    is the route's require_action("edit_intake"); the audit trail records who. Mirrors
    application.service.update."""
    current = await queries.get_intake_status(conn, intake_id=intake_id)
    if current is None:
        return None
    if current["intake_status_code"] in _LOCKED_STATUSES:
        raise IntakeConflict("only a revisable (pre-approval) intake can be edited")
    async with conn.transaction():
        row = await queries.update_intake(
            conn, intake_id=intake_id, title=body.title, description=body.description
        )
        if row is None:  # raced into a locked status between the gate read and the guarded UPDATE
            raise IntakeConflict("only a revisable (pre-approval) intake can be edited")
    return Intake(**row)


async def withdraw_intake(
    conn: AsyncConnection, intake_id: UUID, ctx: AuthContext
) -> Intake | None:
    """Cancel the intake's open approval — the *requester* withdrawing their submission (gated
    edit_intake). The intake drops back to a revisable draft (status unchanged, as application
    withdraw leaves the app 'pending'). None => 404; raises IntakeConflict (409) if nothing is open.
    Mirrors application.service.withdraw."""
    current = await queries.get_intake_status(conn, intake_id=intake_id)
    if current is None:
        return None
    pending = await queries.get_pending_intake_approval(conn, intake_id=intake_id)
    if pending is None:
        raise IntakeConflict("no open approval to cancel")
    async with conn.transaction():
        await queries.cancel_pending_intake_approvals(conn, intake_id=intake_id)
    return await get_intake(conn, intake_id)


async def delete_intake(conn: AsyncConnection, intake_id: UUID) -> bool | None:
    """Hard-delete a still-revisable intake + its dependents (delete_intake action; pre-approval
    only). None => 404; raises IntakeConflict (409) for a locked intake. Requirements cascade via
    FK; the audit trail (audit.status_transition, a soft ref) is left intact. Mirrors
    application.service.delete_application."""
    current = await queries.get_intake_status(conn, intake_id=intake_id)
    if current is None:
        return None
    if current["intake_status_code"] in _LOCKED_STATUSES:
        raise IntakeConflict("only a revisable (pre-approval) intake can be deleted")
    async with conn.transaction():
        await queries.delete_intake_signoffs(conn, intake_id=intake_id)
        await queries.delete_intake_approvals(conn, intake_id=intake_id)
        await queries.delete_intake(conn, intake_id=intake_id)
    return True


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


async def update_requirement(
    conn: AsyncConnection, intake_id: UUID, intake_requirement_id: UUID, req: RequirementUpdate, ctx: AuthContext
) -> Requirement | None:
    """Edit a requirement (kind / title / body) in place. None => no such requirement on this intake
    (-> 404). Gated edit_requirement at the route."""
    row = await queries.update_requirement(
        conn,
        intake_requirement_id=intake_requirement_id,
        intake_id=intake_id,
        requirement_kind_code=req.requirement_kind_code,
        title=req.title,
        body=req.body,
    )
    return Requirement(**row) if row else None


async def delete_requirement(
    conn: AsyncConnection, intake_id: UUID, intake_requirement_id: UUID, ctx: AuthContext
) -> bool | None:
    """Remove a requirement. None => no such requirement on this intake (-> 404). Gated
    edit_requirement at the route."""
    row = await queries.delete_requirement(
        conn, intake_requirement_id=intake_requirement_id, intake_id=intake_id
    )
    return True if row else None


async def list_requirements(conn: AsyncConnection, intake_id: UUID) -> list[Requirement]:
    return [
        Requirement(**r) async for r in queries.list_requirements(conn, intake_id=intake_id)
    ]
