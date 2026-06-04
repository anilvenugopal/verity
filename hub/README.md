# hub/ — the Verity governance hub (Verity-operated)

The platform: governance API, the **Harness Gateway API**, `verity-relay`, the schema/seed
runner, and the portal. Verity-operated; releases on the hub cadence.

Stack: Python 3.12 · FastAPI · psycopg v3 async · **raw SQL via aiosql + a thin repo**
(ADR-0012) · Pydantic v2 · PostgreSQL 18 (pgvector).

Layout (Phase 2):
- `pyproject.toml` — uv-managed; ruff + pytest.
- `src/verity_hub/` — app, config, db pool, the aiosql query loader + repo helpers, routers.
- `db/queries/` — the `.sql` files (raw SQL, one per aggregate).
- `db/migrations/` — numbered `NNNN_*.sql`; the canonical schema + seed is the 0001 baseline.
- `tests/` — pytest against the PG18 testcontainer (the safety net for raw SQL).

Depends only on `../contract/` (publishes the contract; owns the gateway implementation).
Status: scaffold in progress.
