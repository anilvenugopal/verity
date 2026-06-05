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
from verity.hub.auth.models import AuthContext
from verity.hub.db import queries

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
