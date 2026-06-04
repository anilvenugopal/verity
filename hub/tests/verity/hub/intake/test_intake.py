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


def test_classify_sets_codes_partial_and_rejects_bad_code(pg_url):
    # business_owner is in the governance set authorized for reclassify_risk.
    app = _app(pg_url, oid=AUTHOR_OID, roles="business_owner")
    with TestClient(app) as c:
        application_id = c.post("/applications", json={"name": "Claims"}).json()["application_id"]
        intake_id = c.post(
            f"/applications/{application_id}/intakes", json={"title": "Claims triage"}
        ).json()["intake_id"]

        ok = c.post(
            f"/intakes/{intake_id}/classification",
            json={"ai_risk_tier_code": "high", "naic_materiality_code": "material"},
        )
        assert ok.status_code == 200, ok.text
        assert ok.json()["ai_risk_tier_code"] == "high"
        assert ok.json()["naic_materiality_code"] == "material"
        assert ok.json()["materiality_tier_code"] is None  # not supplied -> unchanged

        # Partial update: a new subset leaves the previously-set code intact.
        ok2 = c.post(f"/intakes/{intake_id}/classification", json={"materiality_tier_code": "critical"})
        assert ok2.status_code == 200
        assert ok2.json()["ai_risk_tier_code"] == "high"
        assert ok2.json()["materiality_tier_code"] == "critical"

        # Invalid reference code -> 400 naming the field (D-INT-7), not 500.
        bad = c.post(f"/intakes/{intake_id}/classification", json={"ai_risk_tier_code": "bogus"})
        assert bad.status_code == 400
        assert "ai_risk_tier_code" in bad.json()["detail"]

        # Empty subset -> 422 (request validation).
        assert c.post(f"/intakes/{intake_id}/classification", json={}).status_code == 422


def test_status_change_is_audited_in_one_txn(pg_url):
    # business_owner is in the governance set authorized for triage_intake.
    app = _app(pg_url, oid=AUTHOR_OID, roles="business_owner")
    with TestClient(app) as c:
        application_id = c.post("/applications", json={"name": "Audited"}).json()["application_id"]
        intake_id = c.post(
            f"/applications/{application_id}/intakes", json={"title": "Move me"}
        ).json()["intake_id"]

        r = c.post(
            f"/intakes/{intake_id}/status",
            json={"to_status_code": "in_review", "reason": "meets criteria"},
        )
        assert r.status_code == 200, r.text
        assert r.json()["intake_status_code"] == "in_review"

        # Invalid status code -> 400 (fk_intake_status), and the whole change rolls back: no
        # second audit row, status stays in_review.
        bad = c.post(f"/intakes/{intake_id}/status", json={"to_status_code": "bogus"})
        assert bad.status_code == 400
        assert c.get(f"/intakes/{intake_id}").json()["intake_status_code"] == "in_review"

    # Exactly one audit row, fully attributed (D4 / D-INT-1).
    with psycopg.connect(pg_url) as conn:
        rows = conn.execute(
            "SELECT entity_type, status_field, from_code, to_code, acting_role_code, actor_id, reason "
            "FROM audit.status_transition WHERE entity_id = %s ORDER BY created_at",
            (intake_id,),
        ).fetchall()
    assert len(rows) == 1
    entity_type, status_field, from_code, to_code, acting_role, actor_id, reason = rows[0]
    assert (entity_type, status_field) == ("intake", "intake_status_code")
    assert (from_code, to_code) == ("proposed", "in_review")
    assert acting_role == "business_owner"
    assert actor_id is not None
    assert reason == "meets criteria"


def test_add_requirement_embedding_null_and_list(pg_url):
    # business_owner is in the authoring set authorized for edit_requirement.
    app = _app(pg_url, oid=AUTHOR_OID, roles="business_owner")
    with TestClient(app) as c:
        application_id = c.post("/applications", json={"name": "Reqs"}).json()["application_id"]
        intake_id = c.post(
            f"/applications/{application_id}/intakes", json={"title": "Has requirements"}
        ).json()["intake_id"]

        r = c.post(
            f"/intakes/{intake_id}/requirements",
            json={"requirement_kind_code": "business", "title": "Explainability",
                  "body": "Decisions must cite features"},
        )
        assert r.status_code == 201, r.text
        req = r.json()
        assert req["requirement_status_code"] == "draft"  # DB default
        assert "embedding" not in req  # not exposed at the boundary (D-INT-6)
        requirement_id = req["intake_requirement_id"]

        lst = c.get(f"/intakes/{intake_id}/requirements")
        assert lst.status_code == 200
        assert [x["intake_requirement_id"] for x in lst.json()] == [requirement_id]

        # Invalid kind -> 400 naming the field (D-INT-7).
        bad = c.post(
            f"/intakes/{intake_id}/requirements",
            json={"requirement_kind_code": "bogus", "title": "x", "body": "y"},
        )
        assert bad.status_code == 400
        assert "requirement_kind_code" in bad.json()["detail"]

    # embedding is genuinely null in the row (deferred — D-INT-6).
    with psycopg.connect(pg_url) as conn:
        embedding = conn.execute(
            "SELECT embedding FROM core.intake_requirement WHERE intake_requirement_id = %s",
            (requirement_id,),
        ).fetchone()[0]
    assert embedding is None
