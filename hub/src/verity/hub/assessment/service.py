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

from verity.hub.assessment.models import AssessmentInput, AssessmentView, Computed, RevisionMeta
from verity.hub.assessment.rules import UNACCEPTABLE_NOTE, compute_tier
from verity.hub.auth.models import AuthContext
from verity.hub.db import queries
from verity.hub.intake import service as intake_service
from verity.hub.intake.models import IntakeClassify, IntakeStatusChange


# reference.data_classification is tier-ordered (tier1_public < … < tier4_pii_restricted).
_CLASSIFICATION_RANK = {
    "tier1_public": 1, "tier2_internal": 2, "tier3_confidential": 3, "tier4_pii_restricted": 4,
}
_CONFIDENTIAL_RANK = 3


def _check_ceiling(classification: str, pii_presence: str | None, app_ceiling: str | None) -> None:
    """Enforce FR-IN-018: intake classification ≤ app ceiling; PII ⇒ ≥ confidential. Raises
    ValueError (→ 400). Unknown codes are left to the FK (also → 400)."""
    rank = _CLASSIFICATION_RANK.get(classification)
    if rank is None:
        return
    ceiling_rank = _CLASSIFICATION_RANK.get(app_ceiling or "")
    if ceiling_rank is not None and rank > ceiling_rank:
        raise ValueError(f"data classification '{classification}' exceeds the application ceiling '{app_ceiling}'")
    if pii_presence and pii_presence != "none" and rank < _CONFIDENTIAL_RANK:
        raise ValueError("PII present requires a data classification of at least tier3_confidential")


_TERMINAL_STATUSES = {"rejected", "retired"}


class AssessmentConflict(Exception):
    """A 409 — e.g. assessing an intake that is already in a terminal status (U1)."""


async def capture(conn: AsyncConnection, intake_id: UUID, body: AssessmentInput, ctx: AuthContext) -> AssessmentView | None:
    """Store a new assessment revision. None => the intake does not exist (404)."""
    intake = await intake_service.get_intake(conn, intake_id)
    if intake is None:
        return None
    if intake.intake_status_code in _TERMINAL_STATUSES:  # U1: no re-assessing a terminal intake
        raise AssessmentConflict(f"cannot assess an intake in terminal status '{intake.intake_status_code}'")
    answers = body.model_dump()
    tier, materiality = compute_tier(body.ai_decision_impact)  # inherent (FR-AS-008)
    classification = body.data.data_classification_code
    # US3: enforce the application ceiling before any write (FR-IN-018).
    ceiling_row = await queries.get_intake_app_ceiling(conn, intake_id=intake_id)
    _check_ceiling(classification, body.data.pii_presence, ceiling_row["app_ceiling"] if ceiling_row else None)
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
        # US2: set the intake's inherent tier/materiality (reuse the intake classify path).
        intake = await intake_service.classify_intake(
            conn, intake_id,
            IntakeClassify(ai_risk_tier_code=tier, naic_materiality_code=materiality), ctx,
        )
        status_code = intake.intake_status_code if intake else None
        # US3: set the intake's actual data classification (ceiling already validated).
        await queries.set_intake_classification(conn, intake_id=intake_id, data_classification_code=classification)
        auto_rejected = False
        if tier == "unacceptable":  # FR-IN-004 safety stop — audited auto-reject
            await intake_service.change_status(
                conn, intake_id,
                IntakeStatusChange(to_status_code="rejected", reason=UNACCEPTABLE_NOTE), ctx,
            )
            status_code, auto_rejected = "rejected", True
    computed = Computed(
        ai_risk_tier_code=tier, naic_materiality_code=materiality,
        data_classification_code=classification,
        intake_status_code=status_code, auto_rejected=auto_rejected,
    )
    return AssessmentView(
        intake_id=intake_id, revision=row["revision"], assessment=answers,
        computed=computed, created_at=row["created_at"],
    )


async def get_current(conn: AsyncConnection, intake_id: UUID) -> AssessmentView | None:
    row = await queries.get_current_assessment(conn, intake_id=intake_id)
    if row is None:
        return None
    computed = None
    intake = await intake_service.get_intake(conn, intake_id)
    if intake is not None:
        computed = Computed(
            ai_risk_tier_code=intake.ai_risk_tier_code,
            naic_materiality_code=intake.naic_materiality_code,
            data_classification_code=row["assessment"].get("data", {}).get("data_classification_code"),
            intake_status_code=intake.intake_status_code,
            auto_rejected=intake.intake_status_code == "rejected",
        )
    return AssessmentView(
        intake_id=row["intake_id"], revision=row["revision"],
        assessment=row["assessment"], computed=computed, created_at=row["created_at"],
    )


async def list_revisions(conn: AsyncConnection, intake_id: UUID) -> list[RevisionMeta]:
    return [RevisionMeta(**r) async for r in queries.list_revisions(conn, intake_id=intake_id)]
