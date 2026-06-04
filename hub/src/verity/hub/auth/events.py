"""Append-only auth-event audit (FR-024). Best-effort: never blocks or fails-open the request."""
from __future__ import annotations

import logging

from ..db import queries

logger = logging.getLogger("verity.hub.auth")


async def emit_auth_event(
    pool,
    *,
    event_type: str,
    outcome: str,
    request_id: str,
    reason_code: str | None = None,
    actor_id: str | None = None,
    action_code: str | None = None,
    resource: str | None = None,
    ip: str | None = None,
) -> None:
    try:
        async with pool.connection() as conn:
            await queries.insert_auth_event(
                conn,
                event_type=event_type,
                outcome=outcome,
                reason_code=reason_code,
                actor_id=actor_id,
                action_code=action_code,
                resource=resource,
                request_id=request_id,
                ip=ip,
            )
    except Exception:  # FR-024: audit failure must not block/fail-open the request path
        logger.warning("auth_event write failed (non-fatal)", exc_info=True)
