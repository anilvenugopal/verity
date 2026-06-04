"""JIT provisioning of the identity principal (FR-006a)."""
from __future__ import annotations

from ..db import queries


async def jit_provision(conn, *, tenant_id, microsoft_oid, display_name, email, upn) -> str:
    """Upsert the human actor + account_user, returning actor_id. The single code path that
    creates a user row (FR-006a). A concurrent first-login may unique-violate account_user;
    the caller retries with a fresh connection (resolves to the existing row)."""
    row = await queries.provision_actor(
        conn,
        tenant_id=tenant_id,
        microsoft_oid=microsoft_oid,
        display_name=display_name,
        email=email,
        upn=upn,
    )
    return str(row[0])
