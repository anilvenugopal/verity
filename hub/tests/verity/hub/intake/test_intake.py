"""Mirrors verity/hub/intake/* — US1 end-to-end on PG18: onboard an application, create an intake
under it, read both, with the action gate allowing an authoring principal and denying a viewer.
Asserts attribution (actor + acting role) is recorded server-side (D6)."""
from __future__ import annotations

import os

import psycopg
import pytest
from fastapi.testclient import TestClient
from testcontainers.postgres import PostgresContainer

from verity.hub import migrate
from verity.hub.config import get_settings

AUTHOR_OID = "aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa"
VIEWER_OID = "bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb"


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


def test_onboard_create_and_read(pg_url):
    # business_owner authorizes both onboard_application and create_intake.
    app = _app(pg_url, oid=AUTHOR_OID, roles="business_owner")
    with TestClient(app) as c:
        r = c.post("/applications", json={"name": "Underwriting", "description": "demo"})
        assert r.status_code == 201, r.text
        application_id = r.json()["application_id"]

        ir = c.post(f"/applications/{application_id}/intakes", json={"title": "Submission triage"})
        assert ir.status_code == 201, ir.text
        intake = ir.json()
        intake_id = intake["intake_id"]
        assert intake["application_id"] == application_id
        assert intake["intake_status_code"] == "proposed"  # DB default; classification still null
        assert intake["ai_risk_tier_code"] is None

        g = c.get(f"/intakes/{intake_id}")
        assert g.status_code == 200
        assert g.json()["title"] == "Submission triage"

        lst = c.get(f"/applications/{application_id}/intakes")
        assert lst.status_code == 200
        assert any(i["intake_id"] == intake_id for i in lst.json())

    # Attribution recorded server-side (D6): actor set, acting role is a held authoring role.
    with psycopg.connect(pg_url) as conn:
        actor_id, role = conn.execute(
            "SELECT created_by_actor_id, created_role_code FROM core.intake WHERE intake_id = %s",
            (intake_id,),
        ).fetchone()
        assert actor_id is not None
        assert role == "business_owner"


def test_viewer_denied_on_create_allowed_on_read(pg_url):
    app = _app(pg_url, oid=VIEWER_OID, roles="viewer")
    with TestClient(app) as c:
        denied = c.post("/applications", json={"name": "ShouldNotExist"})
        assert denied.status_code == 403
        assert denied.json()["code"] == "forbidden"
        assert c.get("/applications").status_code == 200


def test_unknown_application_is_404(pg_url):
    app = _app(pg_url, oid=AUTHOR_OID, roles="business_owner")
    missing = "00000000-0000-0000-0000-0000000000ff"
    with TestClient(app) as c:
        assert c.get(f"/applications/{missing}").status_code == 404
        assert c.post(f"/applications/{missing}/intakes", json={"title": "x"}).status_code == 404
