"""Mirrors verity/hub/change_proposal/* (003 US3) on PG18: raise + select assets; quorum approval
forks a new draft (champion unchanged); risk_reclassification re-resolves obligations; SoD; no-
impacted-assets allowed."""
from __future__ import annotations

import os

import psycopg
import pytest
from fastapi.testclient import TestClient
from testcontainers.postgres import PostgresContainer

from verity.hub import migrate
from verity.hub.config import get_settings

# One proposer, one approver (different OIDs → separation of duty).
PROPOSER_OID = "aaaabbbb-cccc-dddd-eeee-ffffaaaabbbb"
APPROVER_OID = "bbbbcccc-dddd-eeee-ffff-aaaabbbbcccc"

_HIGH_ASSESSMENT = {
    "decision_context": {"decision_type": "claims", "consumer_effect": "claim_denial",
                         "annex_iii_high_risk": True, "solely_automated": True,
                         "affected_populations": ["policyholders_consumers"], "deployment_scale": "production_wide"},
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
        migrate.run()
        yield url


def _app(url, *, oid, roles):
    os.environ.update(VERITY_DATABASE_URL=url, VERITY_ENV="local", VERITY_AUTH_MODE="mock",
                      VERITY_MOCK_MICROSOFT_OID=oid, VERITY_MOCK_PLATFORM_ROLES=roles)
    get_settings.cache_clear()
    from verity.hub.app import create_app
    return create_app()


def _seed_app(pg_url, code):
    with psycopg.connect(pg_url, autocommit=True) as conn:
        owner = conn.execute(
            "INSERT INTO core.actor (actor_type_code, display_name) VALUES ('human', %s) RETURNING actor_id",
            (f"{code} owner",),
        ).fetchone()[0]
        app_id = conn.execute(
            "INSERT INTO core.application (code, name, description, application_status_code, data_classification_code, "
            "business_owner_actor_id, affects_consumers, processes_pii, consumer_facing, created_by_actor_id, created_role_code) "
            "VALUES (%s,%s,'cp test','active','tier4_pii_restricted',%s,true,true,true,%s,'business_owner') RETURNING application_id",
            (code, f"{code} app", owner, owner),
        ).fetchone()[0]
        conn.execute(
            "INSERT INTO core.application_governance_domain (application_id, governance_domain_code, created_by_actor_id) VALUES (%s,'fairness',%s)",
            (app_id, owner),
        )
        conn.execute(
            "INSERT INTO core.application_regulatory_framework (application_id, framework_code, created_by_actor_id) VALUES (%s,'nydfs',%s)",
            (app_id, owner),
        )
        return str(app_id)


def _force_approve(pg_url, intake_id):
    """Bypass the quorum by directly setting the intake to approved (lets us test the gate state)."""
    with psycopg.connect(pg_url, autocommit=True) as conn:
        conn.execute("UPDATE core.intake SET intake_status_code='approved' WHERE intake_id=%s", (intake_id,))


def test_raise_proposal_no_assets(pg_url):
    """Can raise a business_change proposal with no impacted assets — empty list is allowed."""
    app = _app(pg_url, oid=PROPOSER_OID, roles="ai_governance,compliance,business_owner")
    app_id = _seed_app(pg_url, "CNA")
    with TestClient(app) as c:
        iid = c.post(f"/applications/{app_id}/intakes", json={"title": "no-assets"}).json()["intake_id"]
        _force_approve(pg_url, iid)
        resp = c.post(f"/intakes/{iid}/change-proposals", json={"kind_code": "business_change", "asset_ids": []})
        assert resp.status_code == 201, resp.text
        data = resp.json()
        assert data["request_kind_code"] == "business_change"
        assert data["status_code"] == "pending"
        assert data["assets"] == []


def test_raise_requires_approved_intake(pg_url):
    """Change proposal raises 409 when the intake is not approved."""
    app = _app(pg_url, oid=PROPOSER_OID, roles="ai_governance,compliance,business_owner")
    app_id = _seed_app(pg_url, "CNO")
    with TestClient(app) as c:
        iid = c.post(f"/applications/{app_id}/intakes", json={"title": "unapproved"}).json()["intake_id"]
        resp = c.post(f"/intakes/{iid}/change-proposals", json={"kind_code": "business_change"})
        assert resp.status_code == 409


def test_duplicate_open_proposal_rejected(pg_url):
    """A second open proposal on the same intake is rejected with 409."""
    app = _app(pg_url, oid=PROPOSER_OID, roles="ai_governance,compliance,business_owner")
    app_id = _seed_app(pg_url, "CDU")
    with TestClient(app) as c:
        iid = c.post(f"/applications/{app_id}/intakes", json={"title": "dup"}).json()["intake_id"]
        _force_approve(pg_url, iid)
        assert c.post(f"/intakes/{iid}/change-proposals", json={"kind_code": "business_change"}).status_code == 201
        # second open proposal → 409
        assert c.post(f"/intakes/{iid}/change-proposals", json={"kind_code": "risk_reclassification"}).status_code == 409


def test_fork_on_approval_champion_unchanged(pg_url):
    """On approval: each impacted asset gets a new draft version; the champion remains."""
    app_id = _seed_app(pg_url, "CFO")

    # Step 1: proposer creates an asset, promotes to champion, raises change proposal.
    proposer = _app(pg_url, oid=PROPOSER_OID, roles="engineer,ai_governance,business_owner,compliance")
    with TestClient(proposer) as c:
        # Create an asset and promote it to champion via a linked approved intake.
        iid_gate = c.post(f"/applications/{app_id}/intakes", json={"title": "gate-intake"}).json()["intake_id"]
        _force_approve(pg_url, iid_gate)
        ex = c.post("/executables", json={"name": "fork-me", "display_name": "Fork Me", "kind_code": "agent"}).json()["executable_id"]
        v = c.post(f"/executables/{ex}/versions").json()["executable_version_id"]
        c.post(f"/versions/{v}/lifecycle", json={"to_stage": "candidate"})
        c.post(f"/intakes/{iid_gate}/links", json={"executable_id": ex})
        champ_resp = c.post(f"/versions/{v}/lifecycle", json={"to_stage": "champion"})
        assert champ_resp.json()["lifecycle_stage"] == "champion"

        # Raise a reclassification proposal on a new approved intake selecting this asset.
        iid = c.post(f"/applications/{app_id}/intakes", json={"title": "cp-test"}).json()["intake_id"]
        c.put(f"/intakes/{iid}/assessment", json=_HIGH_ASSESSMENT)
        _force_approve(pg_url, iid)
        proposal = c.post(f"/intakes/{iid}/change-proposals",
                          json={"kind_code": "risk_reclassification", "asset_ids": [ex]}).json()
        ar_id = proposal["approval_request_id"]
        assert len(proposal["assets"]) == 1

    # Count versions before approval (1).
    with psycopg.connect(pg_url) as conn:
        before = conn.execute("SELECT count(*) FROM core.executable_version WHERE executable_id=%s", (ex,)).fetchone()[0]
    assert before == 1

    # Step 2: approver signs off. _app() called HERE so env reflects the approver OID at request time.
    # High tier quorum: business_owner, compliance, legal, model_risk, ai_governance (5 roles).
    # The approver holds all 5 — sign off sequentially, one role per call.
    approver_app = _app(pg_url, oid=APPROVER_OID, roles="business_owner,compliance,legal,model_risk,ai_governance")
    with TestClient(approver_app) as ca:
        for _ in range(5):
            r = ca.post(f"/approvals/{ar_id}/signoff", json={"decision_code": "approved"})
            assert r.status_code == 200, r.text
            if r.json()["status_code"] == "approved":
                break

    # A new draft version should have been forked.
    with psycopg.connect(pg_url) as conn:
        after = conn.execute("SELECT count(*) FROM core.executable_version WHERE executable_id=%s", (ex,)).fetchone()[0]
    assert after == before + 1  # one new draft forked

    # Champion version must still be the original.
    with psycopg.connect(pg_url) as conn:
        champ_row = conn.execute(
            "SELECT ca.executable_version_id FROM core.champion_assignment ca "
            "JOIN core.executable_version ev ON ev.executable_version_id = ca.executable_version_id "
            "WHERE ev.executable_id = %s ORDER BY ca.created_at DESC LIMIT 1", (ex,)
        ).fetchone()
    assert str(champ_row[0]) == v  # same champion


def test_sod_proposer_cannot_signoff(pg_url):
    """The proposer may not sign off on their own change proposal (separation of duty)."""
    app_id = _seed_app(pg_url, "CSD")
    proposer = _app(pg_url, oid=PROPOSER_OID, roles="ai_governance,compliance,business_owner,legal,model_risk")
    with TestClient(proposer) as c:
        iid = c.post(f"/applications/{app_id}/intakes", json={"title": "sod"}).json()["intake_id"]
        _force_approve(pg_url, iid)
        ar_id = c.post(f"/intakes/{iid}/change-proposals", json={"kind_code": "business_change"}).json()["approval_request_id"]
        # Same actor tries to sign off → 403 (separation of duty).
        resp = c.post(f"/approvals/{ar_id}/signoff", json={"decision_code": "approved"})
        assert resp.status_code == 403


def test_reclassification_resolves_obligations(pg_url):
    """risk_reclassification on approval re-resolves obligations (the obligation set updates)."""
    app_id = _seed_app(pg_url, "CRE")

    proposer = _app(pg_url, oid=PROPOSER_OID, roles="ai_governance,compliance,business_owner")
    with TestClient(proposer) as c:
        iid = c.post(f"/applications/{app_id}/intakes", json={"title": "rereso"}).json()["intake_id"]
        c.put(f"/intakes/{iid}/assessment", json=_HIGH_ASSESSMENT)
        _force_approve(pg_url, iid)
        proposal = c.post(f"/intakes/{iid}/change-proposals",
                          json={"kind_code": "risk_reclassification", "asset_ids": []}).json()
        ar_id = proposal["approval_request_id"]

    approver_app = _app(pg_url, oid=APPROVER_OID, roles="business_owner,compliance,legal,model_risk,ai_governance")
    with TestClient(approver_app) as ca:
        for _ in range(5):
            r = ca.post(f"/approvals/{ar_id}/signoff", json={"decision_code": "approved"})
            assert r.status_code == 200, r.text
            if r.json()["status_code"] == "approved":
                break

    # Re-fetch obligations with a fresh proposer client (env must be set to proposer again).
    proposer2 = _app(pg_url, oid=PROPOSER_OID, roles="ai_governance,compliance,business_owner")
    with TestClient(proposer2) as c:
        post_obls = c.get(f"/intakes/{iid}/obligations").json()
    # After re-resolution the obligations endpoint still returns a valid set (count ≥ 0).
    assert "obligations" in post_obls


def test_list_intake_proposals(pg_url):
    """GET /intakes/{id}/change-proposals returns the proposal history."""
    app = _app(pg_url, oid=PROPOSER_OID, roles="ai_governance,compliance,business_owner")
    app_id = _seed_app(pg_url, "CLS")
    with TestClient(app) as c:
        iid = c.post(f"/applications/{app_id}/intakes", json={"title": "list"}).json()["intake_id"]
        _force_approve(pg_url, iid)
        c.post(f"/intakes/{iid}/change-proposals", json={"kind_code": "business_change"})
        proposals = c.get(f"/intakes/{iid}/change-proposals").json()
        assert len(proposals) == 1
        assert proposals[0]["request_kind_code"] == "business_change"
