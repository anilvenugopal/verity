"""Mirrors verity/hub/app.py — mock-auth end-to-end (FR-030): provisioning + role resolution
+ action gate + auth_event, via the real HTTP routes on PG18."""
from __future__ import annotations

import os

import psycopg
import pytest
from fastapi.testclient import TestClient
from testcontainers.postgres import PostgresContainer

from verity.hub import migrate
from verity.hub.config import get_settings


@pytest.fixture(scope="module")
def pg_url():
    with PostgresContainer(
        "pgvector/pgvector:pg18", username="postgres", password="postgres", dbname="verity"
    ) as pg:
        url = pg.get_connection_url().replace("+psycopg2", "")
        os.environ.update(VERITY_DATABASE_URL=url, VERITY_ENV="local", VERITY_AUTH_MODE="mock")
        get_settings.cache_clear()
        migrate.run()
        yield url


def _app(url, *, oid, roles):
    os.environ.update(
        VERITY_DATABASE_URL=url, VERITY_ENV="local", VERITY_AUTH_MODE="mock",
        VERITY_MOCK_MICROSOFT_OID=oid, VERITY_MOCK_PLATFORM_ROLES=roles,
    )
    get_settings.cache_clear()
    from verity.hub.app import create_app

    return create_app()


def test_security_principal_is_provisioned_and_allowed(pg_url):
    app = _app(pg_url, oid="11111111-1111-1111-1111-111111111111", roles="security,viewer")
    with TestClient(app) as c:
        me = c.get("/me")
        assert me.status_code == 200
        assert "security" in me.json()["platform_roles"]
        assert c.get("/admin/roles").status_code == 200
    with psycopg.connect(pg_url) as conn:
        assert conn.execute(
            "SELECT count(*) FROM audit.auth_event WHERE reason_code='mock_auth'"
        ).fetchone()[0] > 0


def test_viewer_principal_is_denied(pg_url):
    app = _app(pg_url, oid="22222222-2222-2222-2222-222222222222", roles="viewer")
    with TestClient(app) as c:
        assert c.get("/me").status_code == 200
        r = c.get("/admin/roles")
        assert r.status_code == 403
        assert r.json()["code"] == "forbidden"
    with psycopg.connect(pg_url) as conn:
        assert conn.execute(
            "SELECT count(*) FROM audit.auth_event WHERE event_type='authz_denial'"
        ).fetchone()[0] > 0
