"""Compliance Model browser — read-only, view-gated HTTP routes over the governed metamodel (FR-023).

Surfaces frameworks → provisions → canonical requirements → cumulative tier ladders → controls →
evidence specs, so the source of truth can be validated and maintained. Reads the *current* version
of each SCD-2 row (valid_to = the 2099 sentinel). Direct SQL (read-only portal data, like the
reference router); no mutation — governed editing is a deferred follow-on.
"""
from __future__ import annotations

from fastapi import APIRouter, Depends, HTTPException, Request

from verity.hub.auth.dependencies import require_action
from verity.hub.auth.models import AuthContext
from verity.hub.compliance.models import (
    ControlView,
    EvidenceSpec,
    Framework,
    ProvisionView,
    RequirementDetail,
    RequirementSummary,
    TierView,
)

router = APIRouter(tags=["compliance"])

_CUR = "'2099-12-31 00:00:00+00'"  # the SCD-2 "current version" sentinel


@router.get("/compliance/frameworks", response_model=list[Framework])
async def list_frameworks(request: Request, ctx: AuthContext = Depends(require_action("view"))) -> list[Framework]:
    async with request.app.state.pool.connection() as conn:
        cur = await conn.execute(f"""
            SELECT f.framework_code, f.name, f.authority,
              (SELECT count(*) FROM core.regulatory_provision p
                 WHERE p.framework_code = f.framework_code AND p.valid_to = {_CUR}) AS provision_count,
              (SELECT count(DISTINCT pr.requirement_id)
                 FROM core.regulatory_provision p
                 JOIN core.provision_requirement pr ON pr.provision_id = p.provision_id AND pr.valid_to = {_CUR}
                 WHERE p.framework_code = f.framework_code AND p.valid_to = {_CUR}) AS requirement_count
            FROM core.regulatory_framework f
            ORDER BY requirement_count DESC, f.name
        """)
        return [Framework(**r) for r in await cur.fetchall()]


@router.get("/compliance/requirements", response_model=list[RequirementSummary])
async def list_requirements(request: Request, ctx: AuthContext = Depends(require_action("view"))) -> list[RequirementSummary]:
    async with request.app.state.pool.connection() as conn:
        cur = await conn.execute(f"""
            SELECT cr.requirement_code, cr.governance_domain_code, cr.title,
              ARRAY(SELECT DISTINCT p.framework_code
                      FROM core.provision_requirement pr
                      JOIN core.regulatory_provision p ON p.provision_id = pr.provision_id AND p.valid_to = {_CUR}
                      WHERE pr.requirement_id = cr.requirement_id AND pr.valid_to = {_CUR}
                      ORDER BY p.framework_code) AS frameworks,
              (SELECT max(tier_level) FROM core.requirement_tier rt
                 WHERE rt.requirement_id = cr.requirement_id AND rt.valid_to = {_CUR}) AS max_tier,
              (SELECT count(*) FROM core.requirement_tier rt
                 JOIN core.requirement_control rc ON rc.requirement_tier_id = rt.requirement_tier_id AND rc.valid_to = {_CUR}
                 WHERE rt.requirement_id = cr.requirement_id AND rt.valid_to = {_CUR}) AS control_count
            FROM core.canonical_requirement cr
            WHERE cr.valid_to = {_CUR}
            ORDER BY cr.governance_domain_code, cr.requirement_code
        """)
        return [RequirementSummary(**r) for r in await cur.fetchall()]


@router.get("/compliance/requirements/{requirement_code}", response_model=RequirementDetail)
async def get_requirement(requirement_code: str, request: Request, ctx: AuthContext = Depends(require_action("view"))) -> RequirementDetail:
    async with request.app.state.pool.connection() as conn:
        head = await (await conn.execute(
            f"SELECT requirement_code, governance_domain_code, title, text FROM core.canonical_requirement "
            f"WHERE requirement_code = %(c)s AND valid_to = {_CUR}", {"c": requirement_code})).fetchone()
        if head is None:
            raise HTTPException(404, "requirement not found")

        provisions = [ProvisionView(**r) for r in await (await conn.execute(f"""
            SELECT p.framework_code, p.citation, p.jurisdiction, pr.min_tier_level
            FROM core.canonical_requirement cr
            JOIN core.provision_requirement pr ON pr.requirement_id = cr.requirement_id AND pr.valid_to = {_CUR}
            JOIN core.regulatory_provision p ON p.provision_id = pr.provision_id AND p.valid_to = {_CUR}
            WHERE cr.requirement_code = %(c)s AND cr.valid_to = {_CUR}
            ORDER BY pr.min_tier_level, p.framework_code
        """, {"c": requirement_code})).fetchall()]

        # flat tiers × controls × evidence — nested in Python
        rows = await (await conn.execute(f"""
            SELECT rt.tier_level, rt.title AS tier_title, rt.criteria,
                   c.control_code, c.title AS control_title, c.control_phase_code, c.control_type_code, c.enforcement_action_code,
                   es.evidence_artifact_type_code, es.citable_as
            FROM core.canonical_requirement cr
            JOIN core.requirement_tier rt ON rt.requirement_id = cr.requirement_id AND rt.valid_to = {_CUR}
            LEFT JOIN core.requirement_control rc ON rc.requirement_tier_id = rt.requirement_tier_id AND rc.valid_to = {_CUR}
            LEFT JOIN core.control c ON c.control_id = rc.control_id AND c.valid_to = {_CUR}
            LEFT JOIN core.evidence_specification es ON es.control_id = c.control_id AND es.valid_to = {_CUR}
            WHERE cr.requirement_code = %(c)s AND cr.valid_to = {_CUR}
            ORDER BY rt.tier_level, c.control_code
        """, {"c": requirement_code})).fetchall()

        tiers: dict[int, TierView] = {}
        controls: dict[str, ControlView] = {}
        for r in rows:
            lvl = r["tier_level"]
            if lvl not in tiers:
                tiers[lvl] = TierView(tier_level=lvl, title=r["tier_title"], criteria=r["criteria"], controls=[])
            ccode = r["control_code"]
            if ccode is None:
                continue
            if ccode not in controls:
                controls[ccode] = ControlView(
                    control_code=ccode, title=r["control_title"], control_phase_code=r["control_phase_code"],
                    control_type_code=r["control_type_code"], enforcement_action_code=r["enforcement_action_code"], evidence=[],
                )
                tiers[lvl].controls.append(controls[ccode])
            if r["evidence_artifact_type_code"]:
                controls[ccode].evidence.append(EvidenceSpec(evidence_artifact_type_code=r["evidence_artifact_type_code"], citable_as=r["citable_as"]))

        return RequirementDetail(
            requirement_code=head["requirement_code"], governance_domain_code=head["governance_domain_code"],
            title=head["title"], text=head["text"], provisions=provisions,
            tiers=[tiers[k] for k in sorted(tiers)],
        )
