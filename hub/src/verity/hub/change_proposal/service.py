"""Change-proposal service (003 US3): re-govern an approved intake via a risk_reclassification or
business_change proposal. Reuses the shared approval primitive; the FR-IN-005 tier quorum governs
sign-off. On approval: forks each impacted asset to a new draft version; risk_reclassification
re-runs obligation resolution. D7.
"""
from __future__ import annotations

from uuid import UUID

from psycopg import AsyncConnection
from psycopg.types.json import Json

from verity.hub.approval import service as approval_service
from verity.hub.approval.models import ApprovalRequest
from verity.hub.auth.models import AuthContext, AuthError
from verity.hub.change_proposal.models import ChangeProposalView, ProposalAsset
from verity.hub.db import queries

_CHANGE_KINDS = frozenset({"risk_reclassification", "business_change"})

# FR-IN-005 tier quorum — same as intake approval (reused here for change proposals).
_QUORUM: dict[str, list[str]] = {
    "high": ["business_owner", "compliance", "legal", "model_risk", "ai_governance"],
    "limited": ["business_owner", "compliance", "ai_governance"],
    "minimal": ["business_owner"],
    "unacceptable": [],
}


class ChangeProposalConflict(Exception):
    """409 — duplicate open proposal, intake not approved, or self-approval."""


def _quorum(tier: str | None) -> list[str]:
    return _QUORUM.get(tier or "", [])


async def open_proposal(
    conn: AsyncConnection,
    intake_id: UUID,
    kind_code: str,
    asset_ids: list[UUID],
    ctx: AuthContext,
) -> ChangeProposalView:
    """Open a change proposal for an approved intake. ValueError => 400; ChangeProposalConflict => 409."""
    if kind_code not in _CHANGE_KINDS:
        raise ValueError(f"invalid proposal kind '{kind_code}'")
    gate = await queries.get_intake_tier_status(conn, intake_id=intake_id)
    if gate is None:
        raise ValueError("intake not found")
    if gate["intake_status_code"] != "approved":
        raise ChangeProposalConflict("change proposals may only be raised against an approved intake")
    if (await queries.has_open_change_proposal(conn, intake_id=intake_id))["present"]:
        raise ChangeProposalConflict("an open change proposal already exists for this intake")
    tier = gate["ai_risk_tier_code"]
    required = _quorum(tier)

    async with conn.transaction():
        row = await approval_service.open_request(
            conn, request_kind_code=kind_code, target_intake_id=intake_id,
            opened_by_actor_id=ctx.principal.actor_id, opened_role_code=ctx.acting_role,
        )
        ar_id = row["approval_request_id"]
        for eid in asset_ids:
            await queries.insert_change_proposal_asset(conn, approval_request_id=ar_id, executable_id=eid)

    assets = await _load_assets(conn, ar_id)
    return ChangeProposalView(**row, required_roles=required, signoffs=[], assets=assets)


async def get_request_view(conn: AsyncConnection, approval_request_id: UUID) -> ChangeProposalView | None:
    request = await approval_service.get_request(conn, approval_request_id)
    if request is None:
        return None
    tier = await _tier_for(conn, request)
    signoffs = await approval_service.list_signoffs(conn, approval_request_id)
    assets = await _load_assets(conn, approval_request_id)
    from verity.hub.approval.models import SignoffRecord
    return ChangeProposalView(
        **request, required_roles=_quorum(tier),
        signoffs=[SignoffRecord(**s) for s in signoffs], assets=assets,
    )


async def list_intake_proposals(conn: AsyncConnection, intake_id: UUID) -> list[ChangeProposalView]:
    rows = [r async for r in queries.list_intake_change_proposals(conn, intake_id=intake_id)]
    result = []
    for r in rows:
        tier = r.get("ai_risk_tier_code")  # may not be in the query — derive below
        signoffs = await approval_service.list_signoffs(conn, r["approval_request_id"])
        gate = await queries.get_intake_tier_status(conn, intake_id=intake_id)
        tier = gate["ai_risk_tier_code"] if gate else None
        import json
        raw_assets = r["assets"]
        if isinstance(raw_assets, str):
            raw_assets = json.loads(raw_assets)
        assets = [ProposalAsset(**a) for a in (raw_assets or [])]
        from verity.hub.approval.models import SignoffRecord
        result.append(ChangeProposalView(
            approval_request_id=r["approval_request_id"],
            request_kind_code=r["request_kind_code"],
            status_code=r["status_code"],
            target_intake_id=intake_id,
            target_application_id=None,
            opened_by_actor_id=r["opened_by_actor_id"],
            created_at=r["created_at"],
            required_roles=_quorum(tier),
            signoffs=[SignoffRecord(**s) for s in signoffs],
            assets=assets,
        ))
    return result


async def sign_off(
    conn: AsyncConnection,
    approval_request_id: UUID,
    ctx: AuthContext,
    decision_code: str,
    comment: str | None,
) -> ChangeProposalView | None:
    """Record a sign-off. On full quorum approval: fork impacted assets + re-resolve obligations."""
    request = await approval_service.get_request(conn, approval_request_id)
    if request is None:
        return None
    if request["request_kind_code"] not in _CHANGE_KINDS:
        return None  # not ours — caller should not reach here
    if request["status_code"] != "pending":
        raise ChangeProposalConflict("approval is already resolved")
    if str(ctx.principal.actor_id) == str(request["opened_by_actor_id"]):
        raise AuthError(403, "self_approval", "the submitter may not sign off on their own change proposal")
    intake_id = request["target_intake_id"]
    gate = await queries.get_intake_tier_status(conn, intake_id=intake_id)
    tier = gate["ai_risk_tier_code"] if gate else None
    required = _quorum(tier)

    held_required = set(ctx.principal.platform_roles) & set(required)
    if not held_required:
        raise AuthError(403, "not_required_approver", "you hold no required role for this intake's tier")

    existing = await approval_service.list_signoffs(conn, approval_request_id)
    filled = {s["signed_as_role_code"] for s in existing}
    available = sorted(held_required - filled)
    if not available:
        raise ChangeProposalConflict("your required role(s) have already been signed")
    signed_as = available[0]

    async with conn.transaction():
        await approval_service.insert_signoff(
            conn, approval_request_id=approval_request_id, approver_actor_id=ctx.principal.actor_id,
            signed_as_role_code=signed_as, decision_code=decision_code, comment=comment,
        )
        signoffs = await approval_service.list_signoffs(conn, approval_request_id)
        if any(s["decision_code"] in ("rejected", "requested_changes") for s in signoffs):
            await approval_service.set_request_status(conn, approval_request_id, "rejected")
        elif set(required) <= {s["signed_as_role_code"] for s in signoffs if s["decision_code"] == "approved"}:
            await approval_service.set_request_status(conn, approval_request_id, "approved")
            await _on_approved(conn, approval_request_id, intake_id, request["request_kind_code"], ctx)

    return await get_request_view(conn, approval_request_id)


async def _on_approved(
    conn: AsyncConnection,
    approval_request_id: UUID,
    intake_id: UUID,
    kind_code: str,
    ctx: AuthContext,
) -> None:
    """Side effects on approval: fork each impacted asset → new draft; reclassification re-resolves."""
    assets = [r async for r in queries.list_proposal_assets(conn, approval_request_id=approval_request_id)]
    for asset in assets:
        await _fork_asset(conn, asset["executable_id"], approval_request_id, ctx)
    if kind_code == "risk_reclassification":
        from verity.hub.obligation import service as obligation_service
        await obligation_service.resolve(conn, intake_id, ctx)


async def _fork_asset(
    conn: AsyncConnection,
    executable_id: UUID,
    approval_request_id: UUID,
    ctx: AuthContext,
) -> None:
    """Fork the most-advanced version of an executable → a new draft (champion stays untouched)."""
    ex = await queries.get_executable(conn, executable_id=executable_id)
    kind_code = ex["kind_code"] if ex else "agent"
    champ = await queries.get_champion_version(conn, executable_id=executable_id)
    source_version_id = champ["executable_version_id"] if champ else None
    if source_version_id is None:
        best = await queries.get_best_version(conn, executable_id=executable_id)
        if best:
            source_version_id = best["executable_version_id"]
    n = (await queries.version_count(conn, executable_id=executable_id))["n"]
    semver = f"0.{n + 1}.0"
    v = await queries.create_version(
        conn, executable_id=executable_id, kind_code=kind_code,
        semver=semver, created_by_actor_id=ctx.principal.actor_id, created_role_code=ctx.acting_role,
    )
    await queries.insert_lifecycle_event(
        conn, version_id=v["executable_version_id"], from_state=None, to_state="draft",
        approval_request_id=approval_request_id,
        rationale="forked by change proposal",
        detail=Json({"event": "change_proposal_fork", "source_version_id": str(source_version_id) if source_version_id else None}),
        actor_id=ctx.principal.actor_id, acting_role_code=ctx.acting_role,
    )


async def _tier_for(conn: AsyncConnection, request: dict) -> str | None:
    intake_id = request.get("target_intake_id")
    if intake_id is None:
        return None
    gate = await queries.get_intake_tier_status(conn, intake_id=intake_id)
    return gate["ai_risk_tier_code"] if gate else None


async def _load_assets(conn: AsyncConnection, approval_request_id: UUID) -> list[ProposalAsset]:
    return [
        ProposalAsset(executable_id=r["executable_id"], name=r["name"], kind_code=r["kind_code"])
        async for r in queries.list_proposal_assets(conn, approval_request_id=approval_request_id)
    ]
