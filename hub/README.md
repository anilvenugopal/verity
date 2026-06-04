# hub/ — the Verity governance hub (Verity-operated)

The platform: governance API, the **Harness Gateway API**, `verity-relay`, the schema/seed
runner, and the portal. Verity-operated; releases on the hub cadence.

Stack: Python 3.12 · FastAPI · psycopg v3 async · **raw SQL via aiosql + a thin repo**
(ADR-0012) · Pydantic v2 · PostgreSQL 18 (pgvector).

Layout (Phase 2):
- `pyproject.toml` — uv-managed; ruff + pytest. Distribution `verity-hub`; import package `verity.hub` (PEP 420 namespace).
- `src/verity/hub/` — app, config, db pool, the aiosql query loader + repo helpers, `auth/`, routers.
- `db/queries/` — the `.sql` files (raw SQL, one per aggregate).
- `db/migrations/` — numbered `NNNN_*.sql`; the canonical schema + seed is the 0001 baseline.
- `tests/verity/hub/…` — pytest mirroring the package, run against the PG18 testcontainer.

Depends only on `../contract/` (publishes the contract; owns the gateway implementation).

Dev:
```
uv pip install -e ".[dev]"                 # into a local .venv
python -m verity.hub.migrate reset         # DEV: drop app schemas + rebuild from canonical DDL (ADR-0012)
python -m verity.hub.migrate up            # apply baseline + any numbered migrations
pytest -q                                  # PG18 testcontainer
uvicorn verity.hub.app:app --reload        # VERITY_AUTH_MODE=mock VERITY_ENV=local for local dev
```

Status: foundation scaffold (config · db · migrate/reset · auth wiring) — PG18-tested.
