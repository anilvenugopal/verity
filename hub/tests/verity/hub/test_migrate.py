"""Mirrors verity/hub/migrate.py. Baseline loads the canonical schema + seeds on PG18 and
re-runs idempotently — the safety net for raw SQL (ADR-0012)."""
from __future__ import annotations

import os

import psycopg
from testcontainers.postgres import PostgresContainer

from verity.hub import migrate
from verity.hub.config import get_settings


def test_baseline_loads_and_is_idempotent():
    with PostgresContainer(
        "pgvector/pgvector:pg18", username="postgres", password="postgres", dbname="verity"
    ) as pg:
        url = pg.get_connection_url().replace("+psycopg2", "")
        os.environ.update(VERITY_DATABASE_URL=url, VERITY_ENV="local")
        get_settings.cache_clear()

        migrate.run()

        with psycopg.connect(url) as conn:
            roles = conn.execute("SELECT count(*) FROM reference.role").fetchone()[0]
            tables = conn.execute(
                "SELECT count(*) FROM information_schema.tables "
                "WHERE table_schema IN ('reference','core','audit') AND table_type='BASE TABLE'"
            ).fetchone()[0]
        assert roles > 0
        assert tables > 150

        migrate.run()  # idempotent


def test_reset_recreates_from_clean_ddl():
    """ADR-0012 dev workflow: drop the app schemas + ledger and rebuild from the canonical DDL."""
    with PostgresContainer(
        "pgvector/pgvector:pg18", username="postgres", password="postgres", dbname="verity"
    ) as pg:
        url = pg.get_connection_url().replace("+psycopg2", "")
        os.environ.update(VERITY_DATABASE_URL=url, VERITY_ENV="local")
        get_settings.cache_clear()

        migrate.run()
        with psycopg.connect(url) as conn:
            conn.execute("INSERT INTO reference.role (code, label, sort_order) VALUES ('junk', 'Junk', 999)")
            conn.commit()

        migrate.reset()  # drop + rebuild from clean DDL

        with psycopg.connect(url) as conn:
            # the stray row is gone; the seeded vocab is back
            assert conn.execute("SELECT count(*) FROM reference.role WHERE code='junk'").fetchone()[0] == 0
            assert conn.execute("SELECT count(*) FROM reference.role").fetchone()[0] > 0
