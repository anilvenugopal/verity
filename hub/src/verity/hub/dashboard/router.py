"""Home dashboard quick-stats for the portal landing (read-only, view-gated). Counts come straight
from the live tables; `active_decisions` is 0 until the decision/run log is populated (no data yet —
not faked)."""
from __future__ import annotations

from fastapi import APIRouter, Depends, Request

from verity.hub.auth.dependencies import require_action
from verity.hub.auth.models import AuthContext

router = APIRouter(tags=["dashboard"])


async def _count(conn, sql: str) -> int:
    cur = await conn.execute(sql)
    row = await cur.fetchone()
    return int(row["n"]) if row else 0


@router.get("/dashboard/stats")
async def dashboard_stats(
    request: Request, ctx: AuthContext = Depends(require_action("view"))
) -> dict[str, int]:
    async with request.app.state.pool.connection() as conn:
        return {
            "applications": await _count(conn, "select count(*) as n from core.application"),
            "pending_approvals": await _count(conn, "select count(*) as n from core.approval_request where status_code = 'pending'"),
            "active_decisions": 0,  # no decision/run log yet — surfaced honestly as zero
        }
