"""Application onboarding service (US1): propose a pending application + its compliance perimeter.

One transaction: insert the application (status `pending`), the perimeter join rows (frameworks /
domains / jurisdictions), and any initial (non-owner) app-team grants. Attribution is server-set
from the AuthContext (D6). The PII→ceiling rule (FR-IN-018) is enforced here. The governed
approval that activates the application + writes the owner grant is US2.
"""
from __future__ import annotations

from uuid import UUID

from psycopg import AsyncConnection

from verity.hub.application.models import Application, ApplicationPropose
from verity.hub.approval import service as approval_service
from verity.hub.approval.models import ApprovalRequest
from verity.hub.auth.models import AuthContext, AuthError
from verity.hub.db import queries

_ONBOARDING_KIND = "application_onboarding"

# Governed lifecycle transitions (US3). pending->active is via onboarding approval (US2), not here.
_LEGAL_TRANSITIONS = frozenset({
    ("active", "suspended"), ("suspended", "active"),
    ("active", "retired"), ("suspended", "retired"),
})
_LIFECYCLE_TARGETS = frozenset({"active", "suspended", "retired"})


class OnboardingConflict(Exception):
    """A 409 — e.g. submitting a non-pending application, signing a resolved request, or an
    illegal lifecycle transition."""

# reference.data_classification is ordered by tier (tier1_public < … < tier4_pii_restricted).
_CLASSIFICATION_RANK = {
    "tier1_public": 1, "tier2_internal": 2, "tier3_confidential": 3, "tier4_pii_restricted": 4,
}
_CONFIDENTIAL_RANK = 3


def _to_model(row: dict, frameworks: list[str], domains: list[str], jurisdictions: list[str]) -> Application:
    return Application(
        **row,
        regulatory_framework_codes=frameworks,
        governance_domain_codes=domains,
        jurisdiction_codes=jurisdictions,
    )


async def _perimeter(conn: AsyncConnection, application_id: UUID) -> tuple[list[str], list[str], list[str]]:
    frameworks = [r["framework_code"] async for r in queries.list_application_frameworks(conn, application_id=application_id)]
    domains = [r["governance_domain_code"] async for r in queries.list_application_domains(conn, application_id=application_id)]
    jurisdictions = [r["jurisdiction_code"] async for r in queries.list_application_jurisdictions(conn, application_id=application_id)]
    return frameworks, domains, jurisdictions


async def propose(conn: AsyncConnection, body: ApplicationPropose, ctx: AuthContext) -> Application:
    rank = _CLASSIFICATION_RANK.get(body.data_classification_code)
    if body.processes_pii and rank is not None and rank < _CONFIDENTIAL_RANK:
        raise ValueError("data_classification_code must be at least tier3_confidential when processes_pii is true")

    actor_id = ctx.principal.actor_id
    async with conn.transaction():
        row = await queries.propose_application(
            conn,
            code=body.code,
            name=body.name,
            description=body.description,
            line_of_business_code=body.line_of_business_code,
            data_classification_code=body.data_classification_code,
            business_owner_actor_id=body.business_owner_actor_id,
            affects_consumers=body.affects_consumers,
            processes_pii=body.processes_pii,
            consumer_facing=body.consumer_facing,
            created_by_actor_id=actor_id,
            created_role_code=ctx.acting_role,
        )
        application_id = row["application_id"]
        for framework_code in body.regulatory_framework_codes:
            await queries.add_application_framework(conn, application_id=application_id, framework_code=framework_code, created_by_actor_id=actor_id)
        for governance_domain_code in body.governance_domain_codes:
            await queries.add_application_domain(conn, application_id=application_id, governance_domain_code=governance_domain_code, created_by_actor_id=actor_id)
        for jurisdiction_code in body.jurisdiction_codes:
            await queries.add_application_jurisdiction(conn, application_id=application_id, jurisdiction_code=jurisdiction_code, created_by_actor_id=actor_id)
        for member in body.initial_app_team:
            await queries.add_app_team_grant(
                conn, actor_id=member.actor_id, application_id=application_id,
                app_team_role_code=member.app_team_role_code, granted_by_actor_id=actor_id,
                acting_role_code=ctx.acting_role,
            )
        frameworks, domains, jurisdictions = await _perimeter(conn, application_id)
    return _to_model(row, frameworks, domains, jurisdictions)


async def update(conn: AsyncConnection, application_id: UUID, body: ApplicationPropose, ctx: AuthContext) -> Application | None:
    """Edit a still-pending application in place (pre-activation remediation, e.g. after a rejection).
    None => 404. Raises OnboardingConflict (409) if not pending, AuthError (403) if the caller is
    neither the proposer nor the business owner. Active apps change via change-proposal (deferred)."""
    gate = await queries.get_application_gate(conn, application_id=application_id)
    if gate is None:
        return None
    if gate["application_status_code"] != "pending":
        raise OnboardingConflict("only a pending application can be edited")
    actor = str(ctx.principal.actor_id)
    if actor not in (str(gate["created_by_actor_id"]), str(gate["business_owner_actor_id"])):
        raise AuthError(403, "not_editor", "only the proposer or business owner may edit this application")

    rank = _CLASSIFICATION_RANK.get(body.data_classification_code)
    if body.processes_pii and rank is not None and rank < _CONFIDENTIAL_RANK:
        raise ValueError("data_classification_code must be at least tier3_confidential when processes_pii is true")

    actor_id = ctx.principal.actor_id
    async with conn.transaction():
        row = await queries.update_application(
            conn, application_id=application_id,
            code=body.code, name=body.name, description=body.description,
            line_of_business_code=body.line_of_business_code,
            data_classification_code=body.data_classification_code,
            business_owner_actor_id=body.business_owner_actor_id,
            affects_consumers=body.affects_consumers, processes_pii=body.processes_pii,
            consumer_facing=body.consumer_facing,
        )
        if row is None:  # raced out of pending between the gate read and the guarded UPDATE
            raise OnboardingConflict("only a pending application can be edited")
        await queries.clear_application_frameworks(conn, application_id=application_id)
        await queries.clear_application_domains(conn, application_id=application_id)
        await queries.clear_application_jurisdictions(conn, application_id=application_id)
        for framework_code in body.regulatory_framework_codes:
            await queries.add_application_framework(conn, application_id=application_id, framework_code=framework_code, created_by_actor_id=actor_id)
        for governance_domain_code in body.governance_domain_codes:
            await queries.add_application_domain(conn, application_id=application_id, governance_domain_code=governance_domain_code, created_by_actor_id=actor_id)
        for jurisdiction_code in body.jurisdiction_codes:
            await queries.add_application_jurisdiction(conn, application_id=application_id, jurisdiction_code=jurisdiction_code, created_by_actor_id=actor_id)
        frameworks, domains, jurisdictions = await _perimeter(conn, application_id)
    return _to_model(row, frameworks, domains, jurisdictions)


async def get_application(conn: AsyncConnection, application_id: UUID) -> Application | None:
    row = await queries.get_application(conn, application_id=application_id)
    if row is None:
        return None
    frameworks, domains, jurisdictions = await _perimeter(conn, application_id)
    return _to_model(row, frameworks, domains, jurisdictions)


async def list_applications(conn: AsyncConnection) -> list[Application]:
    rows = [r async for r in queries.list_applications(conn)]
    out: list[Application] = []
    for row in rows:
        frameworks, domains, jurisdictions = await _perimeter(conn, row["application_id"])
        out.append(_to_model(row, frameworks, domains, jurisdictions))
    return out


# --- US2: governed onboarding approval (over the reusable approval primitive) -------------------

def _required_roles(owner_needed: bool) -> list[str]:
    """The onboarding quorum (D-ONB-1): AI Governance always; the business owner too when they
    were not the proposer."""
    return ["ai_governance"] + (["business_owner"] if owner_needed else [])


def _satisfied(signoffs: list[dict], owner: UUID, owner_needed: bool) -> bool:
    has_ai_gov = any(s["signed_as_role_code"] == "ai_governance" and s["decision_code"] == "approved" for s in signoffs)
    has_owner = (not owner_needed) or any(
        str(s["approver_actor_id"]) == str(owner) and s["decision_code"] == "approved" for s in signoffs
    )
    return has_ai_gov and has_owner


async def submit_for_approval(conn: AsyncConnection, application_id: UUID, ctx: AuthContext) -> ApprovalRequest | None:
    """Open the `application_onboarding` approval for a pending application. None => 404."""
    gate = await queries.get_application_gate(conn, application_id=application_id)
    if gate is None:
        return None
    if gate["application_status_code"] != "pending":
        raise OnboardingConflict(f"application is '{gate['application_status_code']}', not pending")
    owner_needed = gate["business_owner_actor_id"] != gate["created_by_actor_id"]
    async with conn.transaction():
        row = await approval_service.open_request(
            conn, request_kind_code=_ONBOARDING_KIND, target_application_id=application_id,
            opened_by_actor_id=ctx.principal.actor_id, opened_role_code=ctx.acting_role,
        )
    return approval_service.build_view(row, [], _required_roles(owner_needed))


async def change_status(conn: AsyncConnection, application_id: UUID, to_status_code: str, ctx: AuthContext) -> Application | None:
    """Governed lifecycle transition (US3): suspend / retire / reactivate. None => 404; a target
    outside the lifecycle set => ValueError (400); an illegal transition => OnboardingConflict (409)."""
    gate = await queries.get_application_gate(conn, application_id=application_id)
    if gate is None:
        return None
    if to_status_code not in _LIFECYCLE_TARGETS:
        raise ValueError(f"unsupported lifecycle target '{to_status_code}'")
    from_status = gate["application_status_code"]
    if (from_status, to_status_code) not in _LEGAL_TRANSITIONS:
        raise OnboardingConflict(f"illegal transition '{from_status}' -> '{to_status_code}'")
    async with conn.transaction():
        await queries.set_application_status(conn, application_id=application_id, status_code=to_status_code)
    return await get_application(conn, application_id)


async def get_application_approval_view(conn: AsyncConnection, application_id: UUID) -> ApprovalRequest | None:
    """The latest approval for an application, as the read view. None => the app has no approval yet
    (e.g. a saved-but-not-submitted draft). Powers the workspace governance rail."""
    row = await queries.get_latest_application_approval(conn, application_id=application_id)
    if row is None:
        return None
    return await get_request_view(conn, row["approval_request_id"])


async def get_request_view(conn: AsyncConnection, approval_request_id: UUID) -> ApprovalRequest | None:
    """The approval read view with the computed onboarding quorum. None => 404."""
    request = await approval_service.get_request(conn, approval_request_id)
    if request is None:
        return None
    owner_needed = False
    application_id = request["target_application_id"]
    if application_id is not None:
        gate = await queries.get_application_gate(conn, application_id=application_id)
        if gate is not None:
            owner_needed = gate["business_owner_actor_id"] != gate["created_by_actor_id"]
    signoffs = await approval_service.list_signoffs(conn, approval_request_id)
    return approval_service.build_view(request, signoffs, _required_roles(owner_needed))


async def sign_off(conn: AsyncConnection, approval_request_id: UUID, ctx: AuthContext,
                   decision_code: str, comment: str | None) -> ApprovalRequest | None:
    """Record a sign-off on an onboarding approval and resolve it. None => 404.

    Eligibility: only an AI-Governance role-holder or the named business owner may sign (else 403).
    Resolution: any rejection -> rejected; the computed quorum satisfied -> approved + the
    application is activated + the owner's app_owner grant is written (FR-IN-015)."""
    request = await approval_service.get_request(conn, approval_request_id)
    if request is None:
        return None
    application_id = request["target_application_id"]
    if request["request_kind_code"] != _ONBOARDING_KIND or application_id is None:
        raise OnboardingConflict("not an application onboarding request")
    if request["status_code"] != "pending":
        raise OnboardingConflict("approval is already resolved")

    gate = await queries.get_application_gate(conn, application_id=application_id)
    owner = gate["business_owner_actor_id"]
    owner_needed = owner != gate["created_by_actor_id"]
    is_ai_gov = "ai_governance" in ctx.principal.platform_roles
    is_owner = str(ctx.principal.actor_id) == str(owner)
    if not (is_ai_gov or is_owner):
        raise AuthError(403, "not_required_approver", "not a required approver for this onboarding")
    # Self-approval guard (G1): the proposer may not fill the AI-Governance sign-off slot on their
    # own request — they must be a different person from the AI-Gov approver (separation of duty).
    is_proposer = str(ctx.principal.actor_id) == str(request["opened_by_actor_id"])
    if is_ai_gov and is_proposer and not is_owner:
        raise AuthError(403, "self_approval", "the proposer may not sign as AI Governance on their own request")
    signed_as = "ai_governance" if is_ai_gov else "business_owner"

    # U1: prevent duplicate sign-offs for the same role slot (schema UNIQUE enforces at DB level;
    # this check surfaces a clean 409 before the INSERT rather than relying on a UniqueViolation).
    existing = await approval_service.list_signoffs(conn, approval_request_id)
    if any(s["signed_as_role_code"] == signed_as for s in existing):
        raise OnboardingConflict(f"a sign-off for role '{signed_as}' has already been recorded")

    async with conn.transaction():
        await approval_service.insert_signoff(
            conn, approval_request_id=approval_request_id, approver_actor_id=ctx.principal.actor_id,
            signed_as_role_code=signed_as, decision_code=decision_code, comment=comment,
        )
        signoffs = await approval_service.list_signoffs(conn, approval_request_id)
        # A rejection OR a changes-requested closes the approval (status `rejected`) so it never
        # deadlocks with a filled slot — the proposer remediates by editing + re-submitting (which
        # opens a fresh approval). The signoff's decision_code preserves the rejected/changes nuance.
        if any(s["decision_code"] in ("rejected", "requested_changes") for s in signoffs):
            await approval_service.set_request_status(conn, approval_request_id, "rejected")
        elif _satisfied(signoffs, owner, owner_needed):
            await approval_service.set_request_status(conn, approval_request_id, "approved")
            await queries.set_application_active(conn, application_id=application_id)
            granter = next(
                (s["approver_actor_id"] for s in signoffs
                 if s["signed_as_role_code"] == "ai_governance" and s["decision_code"] == "approved"),
                owner,
            )
            await queries.insert_app_owner_grant(
                conn, actor_id=owner, application_id=application_id,
                granted_by_actor_id=granter, acting_role_code="ai_governance",
            )

    request = await approval_service.get_request(conn, approval_request_id)
    signoffs = await approval_service.list_signoffs(conn, approval_request_id)
    return approval_service.build_view(request, signoffs, _required_roles(owner_needed))
