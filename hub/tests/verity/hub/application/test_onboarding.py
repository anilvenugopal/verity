"""Mirrors verity/hub/application/* — US1 end-to-end on PG18: propose a pending application with
its compliance perimeter, read it back, gate allowing an authoring principal and denying a viewer,
with the validation/ceiling/duplicate rules enforced."""
from __future__ import annotations

import os

import psycopg
import pytest
from fastapi.testclient import TestClient
from testcontainers.postgres import PostgresContainer

from verity.hub import migrate
from verity.hub.config import get_settings

AUTHOR_OID = "cccccccc-cccc-cccc-cccc-cccccccccccc"
VIEWER_OID = "dddddddd-dddd-dddd-dddd-dddddddddddd"


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


def _propose_body(code, owner_id, **over):
    body = {
        "code": code,
        "name": f"{code} Application",
        "description": "A governed application onboarded for end-to-end testing purposes.",
        "data_classification_code": "tier3_confidential",
        "regulatory_framework_codes": ["naic_model_bulletin_ai"],
        "governance_domain_codes": ["model_risk", "fairness"],
        "jurisdiction_codes": ["co", "ny"],
        "business_owner_actor_id": owner_id,
        "affects_consumers": True,
        "processes_pii": True,
        "consumer_facing": False,
        "justification": "Underwriting decisions affecting consumers — governed from onboarding.",
    }
    body.update(over)
    return body


def test_propose_pending_application_with_perimeter(pg_url):
    app = _app(pg_url, oid=AUTHOR_OID, roles="business_owner,ai_governance")
    with TestClient(app) as c:
        owner_id = c.get("/me").json()["actor_id"]  # owner == proposer (a real provisioned actor)
        r = c.post("/applications", json=_propose_body("UWC", owner_id))
        assert r.status_code == 201, r.text
        body = r.json()
        assert body["application_status_code"] == "pending"
        assert body["code"] == "UWC"
        assert sorted(body["governance_domain_codes"]) == ["fairness", "model_risk"]
        assert body["regulatory_framework_codes"] == ["naic_model_bulletin_ai"]
        assert sorted(body["jurisdiction_codes"]) == ["co", "ny"]
        application_id = body["application_id"]

        g = c.get(f"/applications/{application_id}")
        assert g.status_code == 200
        assert g.json()["code"] == "UWC"

    # Attribution + pending status recorded server-side (D6, FR-IN-015).
    with psycopg.connect(pg_url) as conn:
        code, status, created_by = conn.execute(
            "SELECT code, application_status_code, created_by_actor_id FROM core.application WHERE application_id = %s",
            (application_id,),
        ).fetchone()
        assert (code, status) == ("UWC", "pending")
        assert created_by is not None


def test_viewer_denied_on_propose(pg_url):
    app = _app(pg_url, oid=VIEWER_OID, roles="viewer")
    with TestClient(app) as c:
        owner_id = c.get("/me").json()["actor_id"]
        denied = c.post("/applications", json=_propose_body("VWX", owner_id))
        assert denied.status_code == 403
        assert denied.json()["code"] == "forbidden"
        assert c.get("/applications").status_code == 200


def test_validation_and_ceiling_and_bad_codes(pg_url):
    app = _app(pg_url, oid=AUTHOR_OID, roles="business_owner,ai_governance")
    with TestClient(app) as c:
        owner_id = c.get("/me").json()["actor_id"]

        # Invalid TLA shape -> 422 (request validation).
        assert c.post("/applications", json=_propose_body("toolong", owner_id)).status_code == 422
        # Empty perimeter list -> 422.
        assert c.post("/applications", json=_propose_body("EMP", owner_id, governance_domain_codes=[])).status_code == 422
        # Missing attestation -> 422.
        missing = _propose_body("ATT", owner_id)
        del missing["processes_pii"]
        assert c.post("/applications", json=missing).status_code == 422
        # Bad reference code -> 400 naming the field (FK).
        bad = c.post("/applications", json=_propose_body("BAD", owner_id, jurisdiction_codes=["bogus"]))
        assert bad.status_code == 400
        assert "jurisdiction" in bad.json()["detail"]
        # processes_pii with classification below confidential -> 400 (ceiling rule, FR-IN-018).
        ceiling = c.post(
            "/applications",
            json=_propose_body("CEI", owner_id, data_classification_code="tier2_internal", processes_pii=True),
        )
        assert ceiling.status_code == 400


def test_duplicate_tla_conflict(pg_url):
    app = _app(pg_url, oid=AUTHOR_OID, roles="business_owner,ai_governance")
    with TestClient(app) as c:
        owner_id = c.get("/me").json()["actor_id"]
        assert c.post("/applications", json=_propose_body("DUP", owner_id)).status_code == 201
        dup = c.post("/applications", json=_propose_body("DUP", owner_id, name="A Different Name"))
        assert dup.status_code == 409
