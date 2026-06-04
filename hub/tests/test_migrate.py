"""Smoke test: the baseline migration loads the canonical schema + seeds on PG18,
and re-running is idempotent. This test IS the safety net for raw SQL (ADR-0012)."""
from __future__ import annotations

import os

import psycopg
from testcontainers.postgres import PostgresContainer

from verity_hub import migrate
from verity_hub.config import get_settings


def test_baseline_loads_and_is_idempotent():
    with PostgresContainer(
        "pgvector/pgvector:pg18", username="postgres", password="postgres", dbname="verity"
    ) as pg:
        url = pg.get_connection_url().replace("+psycopg2", "")
        os.environ["VERITY_DATABASE_URL"] = url
        get_settings.cache_clear()

        migrate.run()  # baseline + seeds

        with psycopg.connect(url) as conn:
            roles = conn.execute("SELECT count(*) FROM reference.role").fetchone()[0]
            tables = conn.execute(
                "SELECT count(*) FROM information_schema.tables "
                "WHERE table_schema IN ('reference','core','audit') AND table_type='BASE TABLE'"
            ).fetchone()[0]
        assert roles > 0, "reference vocab seeded"
        assert tables > 150, "full schema created"

        migrate.run()  # idempotent: baseline already applied, no error
