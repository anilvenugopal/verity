"""Intake assessment service (US1 capture).

Each submit writes a new SCD-2 revision on `core.intake_impact_assessment` in one transaction
(next revision → close the open one → insert). Answers are stored as `jsonb`. Attribution is
server-set (D6). The computed tier/materiality/classification (US2/US3) is layered on this capture
path; US1 returns the stored revision with `computed = None`.
"""
from __future__ import annotations

from uuid import UUID

from psycopg import AsyncConnection
from psycopg.types.json import Json

from verity.hub.assessment.models import AssessmentInput, AssessmentView, RevisionMeta
from verity.hub.auth.models import AuthContext
from verity.hub.db import queries
from verity.hub.intake import service as intake_service


async def _intake_exists(conn: AsyncConnection, intake_id: UUID) -> bool:
    return (await intake_service.get_intake(conn, intake_id)) is not None


async def capture(conn: AsyncConnection, intake_id: UUID, body: AssessmentInput, ctx: AuthContext) -> AssessmentView | None:
    """Store a new assessment revision. None => the intake does not exist (404)."""
    if not await _intake_exists(conn, intake_id):
        return None
    answers = body.model_dump()
    async with conn.transaction():
        revision = (await queries.next_revision(conn, intake_id=intake_id))["revision"]
        await queries.close_current_assessment(conn, intake_id=intake_id)
        row = await queries.insert_assessment_revision(
            conn,
            intake_id=intake_id,
            revision=revision,
            assessment=Json(answers),
            created_by_actor_id=ctx.principal.actor_id,
            created_role_code=ctx.acting_role,
        )
    return AssessmentView(intake_id=intake_id, revision=row["revision"], assessment=answers, created_at=row["created_at"])


async def get_current(conn: AsyncConnection, intake_id: UUID) -> AssessmentView | None:
    row = await queries.get_current_assessment(conn, intake_id=intake_id)
    if row is None:
        return None
    return AssessmentView(
        intake_id=row["intake_id"], revision=row["revision"],
        assessment=row["assessment"], created_at=row["created_at"],
    )


async def list_revisions(conn: AsyncConnection, intake_id: UUID) -> list[RevisionMeta]:
    return [RevisionMeta(**r) async for r in queries.list_revisions(conn, intake_id=intake_id)]
