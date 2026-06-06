"""Reference vocabularies for the portal (read-only, view-gated). The onboard form populates its
dropdowns/chips from here so the choices always match the seeded reference data; the badge system
reads code/label/description + metadata.{tone,icon} from any whitelisted reference list."""
from __future__ import annotations

from fastapi import APIRouter, Depends, HTTPException, Request

from verity.hub.auth.dependencies import require_action
from verity.hub.auth.models import AuthContext

router = APIRouter(tags=["reference"])

# Reference lists the portal may read by name. A whitelist (not the request path) is interpolated
# into the query, so an attacker can never name an arbitrary table. Grow as badges/pickers need it.
_BADGE_TABLES = {
    "application_status", "intake_status", "approval_request_status",
    "lifecycle_state", "materiality_tier", "naic_materiality", "ai_risk_tier",
    "health_status", "harness_instance_status",
}


async def _codes(conn, sql: str) -> list[dict]:
    cur = await conn.execute(sql)
    return [{"code": r["code"], "label": r["label"]} for r in await cur.fetchall()]


@router.get("/reference/onboarding")
async def onboarding_reference(
    request: Request, ctx: AuthContext = Depends(require_action("view"))
) -> dict[str, list[dict]]:
    """All the vocabularies the application-onboarding form needs."""
    async with request.app.state.pool.connection() as conn:
        return {
            "data_classifications": await _codes(conn, "select code, label from reference.data_classification order by sort_order"),
            "lines_of_business": await _codes(conn, "select code, label from reference.line_of_business order by label"),
            "frameworks": await _codes(conn, "select framework_code as code, name as label from core.regulatory_framework order by name"),
            "governance_domains": await _codes(conn, "select code, label from reference.governance_domain order by label"),
            "jurisdictions": await _codes(conn, "select code, label from reference.jurisdiction order by label"),
        }


@router.get("/reference/codes/{table}")
async def reference_codes(
    table: str, request: Request, ctx: AuthContext = Depends(require_action("view"))
) -> list[dict]:
    """Rows of a whitelisted reference list for the badge system: code/label/description plus the
    metadata presentation hints (tone -> colour, icon -> sprite). `table` must be whitelisted."""
    if table not in _BADGE_TABLES:
        raise HTTPException(404, "unknown reference list")
    async with request.app.state.pool.connection() as conn:
        cur = await conn.execute(
            f"select code, label, description, metadata->>'tone' as tone, metadata->>'icon' as icon "
            f"from reference.{table} where is_active order by sort_order"
        )
        return [dict(r) for r in await cur.fetchall()]
