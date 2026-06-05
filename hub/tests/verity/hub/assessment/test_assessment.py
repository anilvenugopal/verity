"""Mirrors verity/hub/assessment/* — US1 capture on PG18: submit the four-tab questionnaire as
SCD-2 revisions, read the current revision + history, with the edit gate denying a viewer."""
from __future__ import annotations

import os

import pytest
from fastapi.testclient import TestClient
from testcontainers.postgres import PostgresContainer

import psycopg

from verity.hub import migrate
from verity.hub.config import get_settings

AUTHOR_OID = "11112222-3333-4444-5555-666677778888"
VIEWER_OID = "99990000-1111-2222-3333-444455556666"


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


def _seed_active_application(pg_url, code, name):
    """An active application with a high ceiling (so the assessment's tier3 classification fits)."""
    with psycopg.connect(pg_url, autocommit=True) as conn:
        owner = conn.execute(
            "INSERT INTO core.actor (actor_type_code, display_name) VALUES ('human', %s) RETURNING actor_id",
            (f"{code} owner",),
        ).fetchone()[0]
        return str(conn.execute(
            "INSERT INTO core.application (code, name, description, application_status_code, "
            "data_classification_code, business_owner_actor_id, affects_consumers, processes_pii, "
            "consumer_facing, created_by_actor_id, created_role_code) VALUES "
            "(%s, %s, %s, 'active', 'tier4_pii_restricted', %s, true, true, false, %s, 'business_owner') "
            "RETURNING application_id",
            (code, name, f"{name} active app for assessment tests.", owner, owner),
        ).fetchone()[0])


def _assessment_body():
    return {
        "ai_decision_impact": {
            "decision_role": "recommends_with_signoff", "decision_domain": "underwriting",
            "affected_population": "policyholders_consumers", "adverse_impact": "coverage_or_claim_denial",
            "human_oversight": {"strategy": "in_the_loop", "threshold": "all decisions"},
            "reversibility": "reversible_with_effort", "gdpr_art22": False, "deployment_scale": "limited",
        },
        "data": {
            "description": "Submission documents and prior claims history.", "sources": ["policy_admin"],
            "data_classification_code": "tier3_confidential", "pii_presence": "direct",
            "lawful_basis": "established", "residency": "in_region", "retention": "7y", "use": "inference",
        },
        "rationale": "Underwriting recommendation affecting policyholders.",
    }


def test_capture_revisions_and_gate(pg_url):
    app = _app(pg_url, oid=AUTHOR_OID, roles="business_owner")
    application_id = _seed_active_application(pg_url, "ASM", "AssessApp")
    with TestClient(app) as c:
        intake_id = c.post(f"/applications/{application_id}/intakes", json={"title": "Assess me"}).json()["intake_id"]

        r1 = c.put(f"/intakes/{intake_id}/assessment", json=_assessment_body())
        assert r1.status_code == 200, r1.text
        assert r1.json()["revision"] == 1
        assert r1.json()["assessment"]["data"]["pii_presence"] == "direct"

        r2 = c.put(f"/intakes/{intake_id}/assessment", json=_assessment_body())
        assert r2.json()["revision"] == 2  # new SCD-2 revision; revision 1 closed

        g = c.get(f"/intakes/{intake_id}/assessment")
        assert g.status_code == 200
        assert g.json()["revision"] == 2  # the current (open) revision

        revs = c.get(f"/intakes/{intake_id}/assessment/revisions")
        assert [x["revision"] for x in revs.json()] == [1, 2]

        # an intake with no assessment yet -> 404
        other = c.post(f"/applications/{application_id}/intakes", json={"title": "no assess"}).json()["intake_id"]
        assert c.get(f"/intakes/{other}/assessment").status_code == 404

    viewer = _app(pg_url, oid=VIEWER_OID, roles="viewer")
    with TestClient(viewer) as c:
        assert c.put(f"/intakes/{intake_id}/assessment", json=_assessment_body()).status_code == 403
        assert c.get(f"/intakes/{intake_id}/assessment").status_code == 200


def test_bad_body_is_422(pg_url):
    app = _app(pg_url, oid=AUTHOR_OID, roles="business_owner")
    application_id = _seed_active_application(pg_url, "BAD", "BadBodyApp")
    with TestClient(app) as c:
        intake_id = c.post(f"/applications/{application_id}/intakes", json={"title": "x"}).json()["intake_id"]
        # missing the required `data` tab -> 422
        body = _assessment_body()
        del body["data"]
        assert c.put(f"/intakes/{intake_id}/assessment", json=body).status_code == 422
