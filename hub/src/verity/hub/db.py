"""Database access: a psycopg v3 async pool + aiosql-loaded raw SQL (ADR-0012).

SQL lives in hub/db/queries/*.sql as named statements; aiosql exposes them as functions.
No ORM. The thin repo helpers live in repo.py.
"""
from __future__ import annotations

import aiosql
from psycopg_pool import AsyncConnectionPool

from .paths import component_root

QUERIES_DIR = component_root() / "db" / "queries"

# Loaded once at import; the psycopg (v3) adapter works with async connections.
# mandatory_parameters=False: we document params in the SQL prose, not aiosql's name spec.
queries = aiosql.from_path(QUERIES_DIR, "apsycopg", mandatory_parameters=False)


def make_pool(database_url: str) -> AsyncConnectionPool:
    """Create (unopened) the async connection pool. Caller opens/closes it (app lifespan)."""
    return AsyncConnectionPool(conninfo=database_url, open=False, min_size=1, max_size=10)
