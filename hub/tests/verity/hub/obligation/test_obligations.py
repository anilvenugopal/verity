"""Mirrors verity/hub/obligation/* (003 US1) on PG18: resolving an intake's obligations from the
seeded metamodel (migrations 0003/0004), deriving status from evidence + exceptions, the tier-
cumulative acid test, and exception sign-off with separation of duty."""
from __future__ import annotations

import os

import psycopg
import pytest
from fastapi.testclient import TestClient
from testcontainers.postgres import PostgresContainer

from verity.hub import migrate
from verity.hub.config import get_settings

AUTHOR_OID = "11112222-3333-4444-5555-666677778888"
APPROVER_OID = "22223333-4444-5555-6666-777788889999"

# A high-tier assessment in a consumer-facing claims domain → resolves fairness obligations.
_BODY = {
    "decision_context": {
        "decision_type": "claims", "consumer_effect": "claim_denial", "annex_iii_high_risk": True,
        "solely_automated": True, "affected_populations": ["policyholders_consumers"], "deployment_scale": "production_wide",
    },
    "data_inventory": [{"name": "FNOL", "direction": "input", "data_type": "document", "source": "internal",
                        "classification": "tier3_confidential", "pii_presence": "direct"}],
    "human_oversight": {"autonomy_level": "recommends_signoff", "stop_mechanism": True, "controls": []},
}


@pytest.fixture(scope="module")
def pg_url():
    with PostgresContainer("pgvector/pgvector:pg18", username="postgres", password="postgres", dbname="verity") as pg:
        url = pg.get_connection_url().replace("+psycopg2", "")
        os.environ.update(VERITY_DATABASE_URL=url, VERITY_ENV="local", VERITY_AUTH_MODE="mock")
        get_settings.cache_clear()
        migrate.run()  # baseline + 0002..0004 (metamodel seed + evidence intake scope)
        yield url


def _app(url, *, oid, roles):
    os.environ.update(VERITY_DATABASE_URL=url, VERITY_ENV="local", VERITY_AUTH_MODE="mock",
                      VERITY_MOCK_MICROSOFT_OID=oid, VERITY_MOCK_PLATFORM_ROLES=roles)
    get_settings.cache_clear()
    from verity.hub.app import create_app
    return create_app()


def _seed_app(pg_url, code, *, domains, frameworks, ceiling="tier4_pii_restricted"):
    """An active application with governance domains + regulatory frameworks (drive resolution)."""
    with psycopg.connect(pg_url, autocommit=True) as conn:
        owner = conn.execute("INSERT INTO core.actor (actor_type_code, display_name) VALUES ('human', %s) RETURNING actor_id", (f"{code} owner",)).fetchone()[0]
        app_id = conn.execute(
            "INSERT INTO core.application (code, name, description, application_status_code, data_classification_code, "
            "business_owner_actor_id, affects_consumers, processes_pii, consumer_facing, created_by_actor_id, created_role_code) "
            "VALUES (%s,%s,%s,'active',%s,%s,true,true,true,%s,'business_owner') RETURNING application_id",
            (code, f"{code} app", "obligation test", ceiling, owner, owner)).fetchone()[0]
        for d in domains:
            conn.execute("INSERT INTO core.application_governance_domain (application_id, governance_domain_code, created_by_actor_id) VALUES (%s,%s,%s)", (app_id, d, owner))
        for f in frameworks:
            conn.execute("INSERT INTO core.application_regulatory_framework (application_id, framework_code, created_by_actor_id) VALUES (%s,%s,%s)", (app_id, f, owner))
        return str(app_id)


def test_resolve_satisfy_and_acid_test(pg_url):
    app = _app(pg_url, oid=AUTHOR_OID, roles="ai_governance,business_owner")
    application_id = _seed_app(pg_url, "OBF", domains=["fairness"], frameworks=["nydfs", "eu_ai_act"])
    with TestClient(app) as c:
        iid = c.post(f"/applications/{application_id}/intakes", json={"title": "ob"}).json()["intake_id"]
        assert c.put(f"/intakes/{iid}/assessment", json=_BODY).status_code == 200  # high → resolves on save

        ob = c.get(f"/intakes/{iid}/obligations").json()
        assert ob["rollup"]["total"] >= 1 and ob["rollup"]["outstanding"] == ob["rollup"]["total"]
        di = next(o for o in ob["obligations"] if o["requirement_code"] == "fair-disparate-impact")
        assert di["status"] == "outstanding" and di["target_tier"] == 3 and len(di["controls"]) == 3  # T1+T2+T3

        for ctl in di["controls"]:
            assert c.post(f"/obligations/{di['intake_obligation_id']}/evidence", json={"control_code": ctl["control_code"]}).status_code == 200
        after = c.get(f"/intakes/{iid}/obligations").json()
        assert next(o for o in after["obligations"] if o["requirement_code"] == "fair-disparate-impact")["status"] == "satisfied"

        # acid test — metamodel query, tier-cumulative
        st = c.get(f"/requirements/fair-disparate-impact/status?intake={iid}&tier=3").json()
        assert st["status"] == "met" and st["unmet_controls"] == []
        # a non-applicable requirement is not_applicable
        assert c.get(f"/requirements/does-not-exist/status?intake={iid}&tier=1").json()["status"] == "not_applicable"


def test_exception_separation_of_duty(pg_url):
    raiser = _app(pg_url, oid=AUTHOR_OID, roles="ai_governance,compliance")
    application_id = _seed_app(pg_url, "OBX", domains=["fairness"], frameworks=["nydfs"])
    with TestClient(raiser) as c:
        iid = c.post(f"/applications/{application_id}/intakes", json={"title": "x"}).json()["intake_id"]
        c.put(f"/intakes/{iid}/assessment", json=_BODY)
        ex = c.post(f"/intakes/{iid}/exceptions", json={
            "requirement_code": "fair-disparate-impact", "waived_tier_level": 3,
            "compensating_controls": "manual", "rationale": "pilot", "expires_at": "2027-01-01T00:00:00Z"}).json()
        exid = ex["compliance_exception_id"]
        # the raiser may NOT sign off their own (separation of duty)
        assert c.post(f"/exceptions/{exid}/signoff", json={"decision": "approved"}).status_code == 403

    approver = _app(pg_url, oid=APPROVER_OID, roles="compliance")
    with TestClient(approver) as c:
        assert c.post(f"/exceptions/{exid}/signoff", json={"decision": "approved"}).status_code == 200
        di = next(o for o in c.get(f"/intakes/{iid}/obligations").json()["obligations"] if o["requirement_code"] == "fair-disparate-impact")
        assert di["status"] == "excepted"
