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


def _seed_active_application(pg_url, code, name, ceiling="tier4_pii_restricted"):
    """An active application with the given data-classification ceiling."""
    with psycopg.connect(pg_url, autocommit=True) as conn:
        owner = conn.execute(
            "INSERT INTO core.actor (actor_type_code, display_name) VALUES ('human', %s) RETURNING actor_id",
            (f"{code} owner",),
        ).fetchone()[0]
        return str(conn.execute(
            "INSERT INTO core.application (code, name, description, application_status_code, "
            "data_classification_code, business_owner_actor_id, affects_consumers, processes_pii, "
            "consumer_facing, created_by_actor_id, created_role_code) VALUES "
            "(%s, %s, %s, 'active', %s, %s, true, true, false, %s, 'business_owner') "
            "RETURNING application_id",
            (code, name, f"{name} active app for assessment tests.", ceiling, owner, owner),
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


def _unacceptable_body():
    """An autonomous decision with no oversight that discriminates against a vulnerable population."""
    body = _assessment_body()
    body["ai_decision_impact"].update({
        "decision_role": "autonomous",
        "affected_population": "vulnerable",
        "adverse_impact": "unfair_discriminatory",
        "human_oversight": {"strategy": "none"},
    })
    return body


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


def test_high_risk_computes_high(pg_url):
    app = _app(pg_url, oid=AUTHOR_OID, roles="business_owner")
    application_id = _seed_active_application(pg_url, "HIR", "HighRisk")
    with TestClient(app) as c:
        intake_id = c.post(f"/applications/{application_id}/intakes", json={"title": "hr"}).json()["intake_id"]
        r = c.put(f"/intakes/{intake_id}/assessment", json=_assessment_body())
        assert r.status_code == 200, r.text
        computed = r.json()["computed"]
        assert computed["ai_risk_tier_code"] == "high"
        assert computed["naic_materiality_code"] == "material"
        assert computed["auto_rejected"] is False
    with psycopg.connect(pg_url) as conn:
        tier = conn.execute(
            "SELECT ai_risk_tier_code FROM core.intake WHERE intake_id = %s", (intake_id,)
        ).fetchone()[0]
        assert tier == "high"


def test_unacceptable_auto_rejects(pg_url):
    app = _app(pg_url, oid=AUTHOR_OID, roles="business_owner")
    application_id = _seed_active_application(pg_url, "UNA", "Unacceptable")
    with TestClient(app) as c:
        intake_id = c.post(f"/applications/{application_id}/intakes", json={"title": "prohibited"}).json()["intake_id"]
        r = c.put(f"/intakes/{intake_id}/assessment", json=_unacceptable_body())
        assert r.status_code == 200, r.text
        computed = r.json()["computed"]
        assert computed["ai_risk_tier_code"] == "unacceptable"
        assert computed["auto_rejected"] is True
        assert computed["intake_status_code"] == "rejected"
    with psycopg.connect(pg_url) as conn:
        status = conn.execute(
            "SELECT intake_status_code FROM core.intake WHERE intake_id = %s", (intake_id,)
        ).fetchone()[0]
        assert status == "rejected"
        audit_rows = conn.execute(
            "SELECT count(*) FROM audit.status_transition WHERE entity_id = %s AND entity_type = 'intake'",
            (intake_id,),
        ).fetchone()[0]
        assert audit_rows == 1


def test_classification_within_ceiling_persists(pg_url):
    app = _app(pg_url, oid=AUTHOR_OID, roles="business_owner")
    application_id = _seed_active_application(pg_url, "CIN", "WithinCeiling")  # ceiling tier4
    with TestClient(app) as c:
        intake_id = c.post(f"/applications/{application_id}/intakes", json={"title": "c"}).json()["intake_id"]
        r = c.put(f"/intakes/{intake_id}/assessment", json=_assessment_body())  # tier3_confidential
        assert r.status_code == 200, r.text
        assert r.json()["computed"]["data_classification_code"] == "tier3_confidential"
    with psycopg.connect(pg_url) as conn:
        dc = conn.execute(
            "SELECT data_classification_code FROM core.intake WHERE intake_id = %s", (intake_id,)
        ).fetchone()[0]
        assert dc == "tier3_confidential"


def test_classification_over_ceiling_is_400(pg_url):
    app = _app(pg_url, oid=AUTHOR_OID, roles="business_owner")
    application_id = _seed_active_application(pg_url, "COV", "OverCeiling", ceiling="tier2_internal")
    with TestClient(app) as c:
        intake_id = c.post(f"/applications/{application_id}/intakes", json={"title": "c"}).json()["intake_id"]
        # assessment tier3_confidential > app ceiling tier2_internal -> 400
        r = c.put(f"/intakes/{intake_id}/assessment", json=_assessment_body())
        assert r.status_code == 400
        assert "ceiling" in r.json()["detail"]


def test_pii_requires_confidential_is_400(pg_url):
    app = _app(pg_url, oid=AUTHOR_OID, roles="business_owner")
    application_id = _seed_active_application(pg_url, "PII", "PiiLow")  # ceiling tier4
    with TestClient(app) as c:
        intake_id = c.post(f"/applications/{application_id}/intakes", json={"title": "c"}).json()["intake_id"]
        body = _assessment_body()
        body["data"]["data_classification_code"] = "tier2_internal"  # below confidential
        body["data"]["pii_presence"] = "direct"  # but PII is present
        r = c.put(f"/intakes/{intake_id}/assessment", json=body)
        assert r.status_code == 400


def test_invalid_enum_value_is_422(pg_url):
    # A1: an out-of-vocabulary tier-driving answer must 422, not silently down-tier.
    app = _app(pg_url, oid=AUTHOR_OID, roles="business_owner")
    application_id = _seed_active_application(pg_url, "ENM", "EnumApp")
    with TestClient(app) as c:
        intake_id = c.post(f"/applications/{application_id}/intakes", json={"title": "e"}).json()["intake_id"]
        body = _assessment_body()
        body["ai_decision_impact"]["decision_role"] = "autonmous"  # typo — not a valid enum
        assert c.put(f"/intakes/{intake_id}/assessment", json=body).status_code == 422


def test_terminal_intake_blocks_assessment(pg_url):
    # U1: re-assessing a terminal (rejected) intake is rejected with 409.
    app = _app(pg_url, oid=AUTHOR_OID, roles="business_owner")
    application_id = _seed_active_application(pg_url, "TRM", "TerminalApp")
    with TestClient(app) as c:
        intake_id = c.post(f"/applications/{application_id}/intakes", json={"title": "t"}).json()["intake_id"]
        assert c.put(f"/intakes/{intake_id}/assessment", json=_unacceptable_body()).status_code == 200  # -> rejected
        assert c.put(f"/intakes/{intake_id}/assessment", json=_assessment_body()).status_code == 409
