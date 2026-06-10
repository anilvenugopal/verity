"""Intake approval service (Slice 4): submit an assessed intake, resolve the tier quorum.

Reuses the Slice-2 approval primitive (`approval.service`) for the request/sign-off rows and the
Slice-1 audited `intake.service.change_status` to move the intake to `approved`. The required roles
are the FR-IN-005 tier quorum, computed from the intake's `ai_risk_tier_code` (D-IAP-2), not stored.
"""
from __future__ import annotations

from uuid import UUID

from psycopg import AsyncConnection

from verity.hub.approval import service as approval_service
from verity.hub.approval.models import ApprovalRequest
from verity.hub.auth.models import AuthContext, AuthError
from verity.hub.db import queries
from verity.hub.intake import service as intake_service
from verity.hub.intake.models import IntakeStatusChange

_INTAKE_KIND = "intake"
_TERMINAL_STATUSES = {"rejected", "retired"}

# FR-IN-005 — tier → required approval roles (the quorum). `unacceptable` is auto-rejected (Slice 3),
# so it never reaches submit; it carries an empty quorum for completeness.
_INTAKE_QUORUM: dict[str, list[str]] = {
    "high": ["business_owner", "compliance", "legal", "model_risk", "ai_governance"],
    "limited": ["business_owner", "compliance", "ai_governance"],
    "minimal": ["business_owner"],
    "unacceptable": [],
}


class IntakeApprovalConflict(Exception):
    """A 409 — terminal intake, duplicate open approval, already-resolved request, or a role slot
    already filled."""


def _quorum(tier: str | None) -> list[str]:
    return _INTAKE_QUORUM.get(tier or "", [])


async def submit_for_approval(conn: AsyncConnection, intake_id: UUID, ctx: AuthContext) -> ApprovalRequest | None:
    """Open a kind=intake approval with the tier quorum. None => 404; ValueError => 400 (no tier);
    IntakeApprovalConflict => 409 (terminal / duplicate)."""
    gate = await queries.get_intake_tier_status(conn, intake_id=intake_id)
    if gate is None:
        return None
    if gate["intake_status_code"] in _TERMINAL_STATUSES:
        raise IntakeApprovalConflict(f"cannot submit an intake in terminal status '{gate['intake_status_code']}'")
    tier = gate["ai_risk_tier_code"]
    if tier is None:
        raise ValueError("intake not yet classified — complete the assessment first")
    required = _quorum(tier)
    if not required:  # U1: a tier with no quorum (unacceptable) has no approval path
        raise IntakeApprovalConflict(f"intake tier '{tier}' has no approval quorum")
    if (await queries.has_open_intake_approval(conn, intake_id=intake_id))["present"]:
        raise IntakeApprovalConflict("an open approval already exists for this intake")
    async with conn.transaction():
        row = await approval_service.open_request(
            conn, request_kind_code=_INTAKE_KIND, target_intake_id=intake_id,
            opened_by_actor_id=ctx.principal.actor_id, opened_role_code=ctx.acting_role,
        )
        if gate["intake_status_code"] == "proposed":  # I2: advance the lifecycle on submit
            await intake_service.change_status(
                conn, intake_id,
                IntakeStatusChange(to_status_code="in_review", reason="submitted for approval"), ctx,
            )
    return approval_service.build_view(row, [], required)


async def get_intake_approval_view(conn: AsyncConnection, intake_id: UUID) -> ApprovalRequest | None:
    """The latest approval for an intake, as the read view. None => never submitted. Mirrors
    application.service.get_application_approval_view; powers the intake detail governance panel."""
    row = await queries.get_latest_intake_approval(conn, intake_id=intake_id)
    if row is None:
        return None
    return await get_request_view(conn, row["approval_request_id"])


async def get_request_view(conn: AsyncConnection, approval_request_id: UUID) -> ApprovalRequest | None:
    request = await approval_service.get_request(conn, approval_request_id)
    if request is None:
        return None
    tier = await _tier_for(conn, request)
    signoffs = await approval_service.list_signoffs(conn, approval_request_id)
    return approval_service.build_view(request, signoffs, _quorum(tier))


async def _tier_for(conn: AsyncConnection, request: dict) -> str | None:
    intake_id = request["target_intake_id"]
    if intake_id is None:
        return None
    gate = await queries.get_intake_tier_status(conn, intake_id=intake_id)
    return gate["ai_risk_tier_code"] if gate else None


async def sign_off(conn: AsyncConnection, approval_request_id: UUID, ctx: AuthContext,
                   decision_code: str, comment: str | None) -> ApprovalRequest | None:
    """Record a sign-off filling a required-role slot the signer holds; resolve the tier quorum."""
    request = await approval_service.get_request(conn, approval_request_id)
    if request is None:
        return None
    if request["status_code"] != "pending":
        raise IntakeApprovalConflict("approval is already resolved")
    if str(ctx.principal.actor_id) == str(request["opened_by_actor_id"]):  # G1: separation of duty
        raise AuthError(403, "self_approval", "the submitter may not sign off on their own intake approval")
    intake_id = request["target_intake_id"]
    tier = await _tier_for(conn, request)
    required = _quorum(tier)

    held_required = set(ctx.principal.platform_roles) & set(required)
    if not held_required:
        raise AuthError(403, "not_required_approver", "you hold no required role for this intake's tier")

    existing = await approval_service.list_signoffs(conn, approval_request_id)
    filled = {s["signed_as_role_code"] for s in existing}
    available = sorted(held_required - filled)
    if not available:
        raise IntakeApprovalConflict("your required role(s) have already been signed")
    signed_as = available[0]

    async with conn.transaction():
        await approval_service.insert_signoff(
            conn, approval_request_id=approval_request_id, approver_actor_id=ctx.principal.actor_id,
            signed_as_role_code=signed_as, decision_code=decision_code, comment=comment,
        )
        signoffs = await approval_service.list_signoffs(conn, approval_request_id)
        # A 'rejected' OR 'requested_changes' sign-off closes the request (status -> rejected; no
        # deadlock) — parity with application onboarding (FR-IN-015a / FR-019). Either way the intake
        # stays at in_review (revisable), so the author can edit & re-submit. This lets the shared
        # sign-off gate offer the same Approve / Request changes / Reject for kind=intake.
        if any(s["decision_code"] in ("rejected", "requested_changes") for s in signoffs):
            await approval_service.set_request_status(conn, approval_request_id, "rejected")
        elif set(required) <= {s["signed_as_role_code"] for s in signoffs if s["decision_code"] == "approved"}:
            await approval_service.set_request_status(conn, approval_request_id, "approved")
            await intake_service.change_status(
                conn, intake_id,
                IntakeStatusChange(to_status_code="approved", reason="approved by the tier quorum"), ctx,
            )

    request = await approval_service.get_request(conn, approval_request_id)
    signoffs = await approval_service.list_signoffs(conn, approval_request_id)
    return approval_service.build_view(request, signoffs, required)
