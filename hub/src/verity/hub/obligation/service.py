"""Obligation service (003 US1): resolve an intake's obligation set from the metamodel, derive each
obligation's status from recorded evidence + valid exceptions, record evidence, and raise/sign-off
compliance exceptions. The metamodel is the source of truth — resolution is a query, not bespoke logic.
"""
from __future__ import annotations

from uuid import UUID

from psycopg import AsyncConnection
from psycopg.types.json import Json

from verity.hub.auth.models import AuthContext, AuthError
from verity.hub.db import queries
from verity.hub.obligation.models import (
    ExceptionInput,
    ExceptionView,
    Obligation,
    ObligationControl,
    ObligationSet,
    RequirementStatus,
    Rollup,
)

_ONTOLOGY_VERSION = "003.metamodel.v1"


class ObligationConflict(Exception):
    """409 — e.g. signing off an already-resolved exception, or self-approval."""


async def resolve(conn: AsyncConnection, intake_id: UUID, ctx: AuthContext) -> int:
    """(Re-)resolve the obligation set for an intake from the metamodel (FR-001/002). Supersedes the
    prior resolution; evidence + exceptions persist (keyed by intake) so derived status survives.
    Returns the obligation count. Runs in the caller's transaction."""
    applicable = [r async for r in queries.resolve_applicable_requirements(conn, intake_id=intake_id)]
    await queries.delete_intake_resolution(conn, intake_id=intake_id)
    if not applicable:
        return 0
    res = await queries.insert_obligation_resolution(
        conn, intake_id=intake_id, ontology_version=_ONTOLOGY_VERSION,
        resolved_by_actor_id=ctx.principal.actor_id, resolved_role_code=ctx.acting_role,
    )
    rid = res["intake_obligation_resolution_id"]
    for a in applicable:
        if a["target_requirement_tier_id"] is None:
            continue
        await queries.insert_obligation(
            conn, resolution_id=rid, canonical_requirement_id=a["requirement_id"],
            governance_domain_code=a["governance_domain_code"], target_requirement_tier_id=a["target_requirement_tier_id"],
        )
    return len(applicable)


async def _status_and_controls(conn: AsyncConnection, intake_id: UUID, requirement_id: UUID, target_tier: int) -> tuple[str, list[ObligationControl]]:
    controls = [ObligationControl(**c) async for c in queries.obligation_controls(
        conn, intake_id=intake_id, requirement_id=requirement_id, target_tier=target_tier)]
    exc = await queries.active_exception(conn, intake_id=intake_id, requirement_id=requirement_id, target_tier=target_tier)
    if exc is not None:
        return "excepted", controls
    if controls and all(c.evidenced for c in controls):
        return "satisfied", controls
    if not controls:
        return "satisfied", controls  # no controls bound at this tier → nothing to evidence
    return "outstanding", controls


async def get_obligation_set(conn: AsyncConnection, intake_id: UUID) -> ObligationSet:
    obligations: list[Obligation] = []
    counts = {"satisfied": 0, "excepted": 0, "outstanding": 0}
    async for o in queries.list_obligations(conn, intake_id=intake_id):
        status, controls = await _status_and_controls(conn, intake_id, o["canonical_requirement_id"], o["target_tier"])
        counts[status] = counts.get(status, 0) + 1
        obligations.append(Obligation(
            intake_obligation_id=o["intake_obligation_id"], requirement_code=o["requirement_code"], title=o["title"],
            governance_domain_code=o["governance_domain_code"], target_tier=o["target_tier"], status=status, controls=controls,
        ))
    total = len(obligations)
    rollup = Rollup(total=total, satisfied=counts["satisfied"], excepted=counts["excepted"],
                    outstanding=counts["outstanding"], all_resolved=(total > 0 and counts["outstanding"] == 0) or total == 0)
    return ObligationSet(intake_id=intake_id, obligations=obligations, rollup=rollup)


async def record_evidence(conn: AsyncConnection, obligation_id: UUID, control_code: str, note: str | None, ctx: AuthContext) -> Obligation | None:
    """Record evidence against a control of an obligation → the obligation becomes satisfied once every
    control for tiers ≤ target is evidenced. None => the obligation does not exist (404)."""
    ob = await queries.intake_for_obligation(conn, obligation_id=obligation_id)
    if ob is None:
        return None
    cf = await queries.control_for_evidence(conn, control_code=control_code)
    if cf is None:
        raise ValueError("unknown control")
    async with conn.transaction():
        await queries.record_evidence(
            conn, intake_id=ob["intake_id"], canonical_requirement_id=ob["canonical_requirement_id"],
            requirement_tier_id=cf["requirement_tier_id"], control_id=cf["control_id"],
            evidence_specification_id=cf["evidence_specification_id"], control_phase_code=cf["control_phase_code"],
            evidence_artifact_type_code=cf["evidence_artifact_type_code"], storage_ref=Json({"note": note}) if note else None,
            produced_by_actor_id=ctx.principal.actor_id, produced_role_code=ctx.acting_role,
        )
    status, controls = await _status_and_controls(conn, ob["intake_id"], ob["canonical_requirement_id"], ob["target_tier"])
    # re-read the obligation header for the response
    async for o in queries.list_obligations(conn, intake_id=ob["intake_id"]):
        if o["intake_obligation_id"] == obligation_id:
            return Obligation(intake_obligation_id=obligation_id, requirement_code=o["requirement_code"], title=o["title"],
                              governance_domain_code=o["governance_domain_code"], target_tier=o["target_tier"], status=status, controls=controls)
    return None


async def requirement_status(conn: AsyncConnection, intake_id: UUID, requirement_code: str, tier: int) -> RequirementStatus:
    """The acid test (FR-020): is requirement R at tier N met for this intake? Tier-cumulative, from
    metamodel queries alone."""
    req = await queries.requirement_id_by_code(conn, code=requirement_code)
    if req is None:
        return RequirementStatus(requirement_code=requirement_code, tier=tier, status="not_applicable")
    status, controls = await _status_and_controls(conn, intake_id, req["requirement_id"], tier)
    mapped = {"satisfied": "met", "excepted": "excepted", "outstanding": "outstanding"}
    return RequirementStatus(
        requirement_code=requirement_code, tier=tier, status=mapped.get(status, status),
        unmet_controls=[c.control_code for c in controls if not c.evidenced],
    )


# ── Exceptions (compliance_exception; approve_exception sign-off, separation of duty) ─────────────
async def raise_exception(conn: AsyncConnection, intake_id: UUID, body: ExceptionInput, ctx: AuthContext) -> ExceptionView:
    req = await queries.requirement_id_by_code(conn, code=body.requirement_code)
    if req is None:
        raise ValueError("unknown requirement")
    async with conn.transaction():
        row = await queries.insert_exception(
            conn, canonical_requirement_id=req["requirement_id"], waived_tier_level=body.waived_tier_level,
            scope_intake_id=intake_id, compensating_controls=body.compensating_controls, rationale=body.rationale,
            expires_at=body.expires_at, opened_by_actor_id=ctx.principal.actor_id, opened_role_code=ctx.acting_role,
        )
    exc = await queries.get_exception(conn, exception_id=row["compliance_exception_id"])
    return ExceptionView(**exc)


async def signoff_exception(conn: AsyncConnection, exception_id: UUID, decision: str, ctx: AuthContext) -> ExceptionView | None:
    exc = await queries.get_exception(conn, exception_id=exception_id)
    if exc is None:
        return None
    if exc["exception_status_code"] != "requested":
        raise ObligationConflict("exception already resolved")
    if str(exc["opened_by_actor_id"]) == str(ctx.principal.actor_id):  # separation of duty
        raise AuthError(403, "self_approval", "the raiser may not sign off on their own exception")
    status = "approved" if decision == "approved" else "rejected"
    async with conn.transaction():
        await queries.set_exception_status(conn, exception_id=exception_id, status=status,
                                           approver_actor_id=ctx.principal.actor_id, signed_as_role_code=ctx.acting_role)
    return ExceptionView(**await queries.get_exception(conn, exception_id=exception_id))
