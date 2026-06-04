"""Database access: a psycopg v3 async pool + aiosql-loaded raw SQL (ADR-0012).

SQL lives in hub/db/queries/*.sql as named statements; aiosql exposes them as functions.
No ORM. The thin repo helpers live in repo.py.
"""
from __future__ import annotations

from pathlib import Path

import aiosql
from psycopg_pool import AsyncConnectionPool

QUERIES_DIR = Path(__file__).resolve().parents[2] / "db" / "queries"

# Loaded once at import; the psycopg (v3) adapter works with async connections.
queries = aiosql.from_path(QUERIES_DIR, "psycopg")


def make_pool(database_url: str) -> AsyncConnectionPool:
    """Create (unopened) the async connection pool. Caller opens/closes it (app lifespan)."""
    return AsyncConnectionPool(conninfo=database_url, open=False, min_size=1, max_size=10)
