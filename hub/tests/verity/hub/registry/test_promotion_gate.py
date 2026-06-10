"""Mirrors verity/hub/registry/* (003 US2) on PG18: the minimal asset primitive + the promotion gate
— advancing to a production-reaching stage (champion) requires a link to an approved intake whose
obligations are all resolved; early stages are exempt; ≤1 intake per asset."""
from __future__ import annotations

import os

import psycopg
import pytest
from fastapi.testclient import TestClient
from testcontainers.postgres import PostgresContainer

from verity.hub import migrate
from verity.hub.config import get_settings

ENG_OID = "33334444-5555-6666-7777-888899990000"
HIGH_BODY = {
    "decision_context": {"decision_type": "claims", "consumer_effect": "claim_denial", "annex_iii_high_risk": True,
                         "solely_automated": True, "affected_populations": ["policyholders_consumers"], "deployment_scale": "production_wide"},
    "data_inventory": [{"name": "x", "direction": "input", "data_type": "document", "source": "internal",
                        "classification": "tier3_confidential", "pii_presence": "direct"}],
    "human_oversight": {"autonomy_level": "recommends_signoff", "stop_mechanism": True, "controls": []},
}


@pytest.fixture(scope="module")
def pg_url():
    with PostgresContainer("pgvector/pgvector:pg18", username="postgres", password="postgres", dbname="verity") as pg:
        url = pg.get_connection_url().replace("+psycopg2", "")
        os.environ.update(VERITY_DATABASE_URL=url, VERITY_ENV="local", VERITY_AUTH_MODE="mock")
        get_settings.cache_clear()
        migrate.run()
        yield url


def _app(url, *, oid, roles):
    os.environ.update(VERITY_DATABASE_URL=url, VERITY_ENV="local", VERITY_AUTH_MODE="mock",
                      VERITY_MOCK_MICROSOFT_OID=oid, VERITY_MOCK_PLATFORM_ROLES=roles)
    get_settings.cache_clear()
    from verity.hub.app import create_app
    return create_app()


def _seed_app(pg_url, code, *, domains, frameworks):
    with psycopg.connect(pg_url, autocommit=True) as conn:
        owner = conn.execute("INSERT INTO core.actor (actor_type_code, display_name) VALUES ('human', %s) RETURNING actor_id", (f"{code}o",)).fetchone()[0]
        app_id = conn.execute(
            "INSERT INTO core.application (code, name, description, application_status_code, data_classification_code, "
            "business_owner_actor_id, affects_consumers, processes_pii, consumer_facing, created_by_actor_id, created_role_code) "
            "VALUES (%s,%s,'t','active','tier4_pii_restricted',%s,true,true,true,%s,'business_owner') RETURNING application_id", (code, code, owner, owner)).fetchone()[0]
        for d in domains:
            conn.execute("INSERT INTO core.application_governance_domain (application_id, governance_domain_code, created_by_actor_id) VALUES (%s,%s,%s)", (app_id, d, owner))
        for f in frameworks:
            conn.execute("INSERT INTO core.application_regulatory_framework (application_id, framework_code, created_by_actor_id) VALUES (%s,%s,%s)", (app_id, f, owner))
        return str(app_id)


def _approve(pg_url, intake_id):
    with psycopg.connect(pg_url, autocommit=True) as conn:
        conn.execute("UPDATE core.intake SET intake_status_code='approved' WHERE intake_id=%s", (intake_id,))


def test_gate_exempt_block_and_pass(pg_url):
    app = _app(pg_url, oid=ENG_OID, roles="engineer,ai_governance,business_owner")
    application_id = _seed_app(pg_url, "GAT", domains=["fairness"], frameworks=["nydfs"])
    with TestClient(app) as c:
        ex = c.post("/executables", json={"name": "scorer", "kind_code": "task"}).json()["executable_id"]
        v = c.post(f"/executables/{ex}/versions").json()["executable_version_id"]
        assert c.post(f"/versions/{v}/lifecycle", json={"to_stage": "candidate"}).json()["lifecycle_stage"] == "candidate"  # exempt
        assert c.post(f"/versions/{v}/lifecycle", json={"to_stage": "champion"}).status_code == 409  # not linked

        # an approved intake with NO obligations → gate passes (all_resolved when total==0)
        iid = c.post(f"/applications/{application_id}/intakes", json={"title": "pass"}).json()["intake_id"]
        _approve(pg_url, iid)
        assert c.post(f"/intakes/{iid}/links", json={"executable_id": ex}).status_code == 201
        # a second intake link is rejected (≤1 per asset)
        i2 = c.post(f"/applications/{application_id}/intakes", json={"title": "x"}).json()["intake_id"]
        assert c.post(f"/intakes/{i2}/links", json={"executable_id": ex}).status_code == 409
        assert c.post(f"/versions/{v}/lifecycle", json={"to_stage": "champion"}).json()["lifecycle_stage"] == "champion"
        assert any(l["top_stage"] == "champion" for l in c.get(f"/intakes/{iid}/links").json())


def test_gate_blocks_on_outstanding_obligation(pg_url):
    app = _app(pg_url, oid=ENG_OID, roles="engineer,ai_governance,business_owner")
    application_id = _seed_app(pg_url, "GAB", domains=["fairness"], frameworks=["nydfs"])
    with TestClient(app) as c:
        ex = c.post("/executables", json={"name": "scorer2", "kind_code": "task"}).json()["executable_id"]
        v = c.post(f"/executables/{ex}/versions").json()["executable_version_id"]
        iid = c.post(f"/applications/{application_id}/intakes", json={"title": "block"}).json()["intake_id"]
        c.put(f"/intakes/{iid}/assessment", json=HIGH_BODY)  # resolves outstanding obligations
        _approve(pg_url, iid)
        c.post(f"/intakes/{iid}/links", json={"executable_id": ex})
        r = c.post(f"/versions/{v}/lifecycle", json={"to_stage": "champion"})
        assert r.status_code == 409 and "outstanding_obligation" in r.json()["detail"]
