"""Mirrors verity/hub/intake_approval/* — Slice 4 e2e on PG18: submit an assessed intake, the
FR-IN-005 tier quorum signs off (separation of duty: the submitter may not sign), and a satisfied
quorum approves the intake (audited; submit also advances proposed→in_review)."""
from __future__ import annotations

import os

import psycopg
import pytest
from fastapi.testclient import TestClient
from testcontainers.postgres import PostgresContainer

from verity.hub import migrate
from verity.hub.config import get_settings

SUBMITTER_OID = "aaaa1111-2222-3333-4444-555566667777"  # engineer: can submit, cannot sign
BO_OID = "bbbb1111-2222-3333-4444-555566667777"          # business_owner
GOV_OID = "dddd1111-2222-3333-4444-555566667777"         # holds the full high quorum
PRIV_OID = "cccc1111-2222-3333-4444-555566667777"        # privacy (approval role, not in any tier quorum)
VIEWER_OID = "eeee1111-2222-3333-4444-555566667777"

_HIGH_QUORUM = ["ai_governance", "business_owner", "compliance", "legal", "model_risk"]


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


def _submitter(url):
    return _app(url, oid=SUBMITTER_OID, roles="engineer")


def _seed_intake(pg_url, code, tier="high", status="proposed"):
    """Directly seed an active app + an intake with a given tier/status (decoupled from assessment)."""
    with psycopg.connect(pg_url, autocommit=True) as conn:
        actor = conn.execute(
            "INSERT INTO core.actor (actor_type_code, display_name) VALUES ('human', %s) RETURNING actor_id",
            (f"{code} actor",),
        ).fetchone()[0]
        app = conn.execute(
            "INSERT INTO core.application (code, name, description, application_status_code, "
            "data_classification_code, business_owner_actor_id, affects_consumers, processes_pii, "
            "consumer_facing, created_by_actor_id, created_role_code) VALUES "
            "(%s, %s, 'x', 'active', 'tier4_pii_restricted', %s, false, false, false, %s, 'business_owner') "
            "RETURNING application_id",
            (code, f"{code} app", actor, actor),
        ).fetchone()[0]
        intake = conn.execute(
            "INSERT INTO core.intake (application_id, title, intake_status_code, ai_risk_tier_code, "
            "created_by_actor_id, created_role_code) VALUES (%s, 'Approve me', %s, %s, %s, 'business_owner') "
            "RETURNING intake_id",
            (app, status, tier, actor),
        ).fetchone()[0]
    return str(intake)


def test_submit_opens_tier_quorum(pg_url):
    high = _seed_intake(pg_url, "HGH", tier="high")
    mini = _seed_intake(pg_url, "MIN", tier="minimal")
    untiered = _seed_intake(pg_url, "NON", tier=None)
    with TestClient(_submitter(pg_url)) as c:
        r = c.post(f"/intakes/{high}/submit", json={})
        assert r.status_code == 201, r.text
        assert sorted(r.json()["required_roles"]) == _HIGH_QUORUM
        assert c.post(f"/intakes/{mini}/submit", json={}).json()["required_roles"] == ["business_owner"]
        assert c.post(f"/intakes/{untiered}/submit", json={}).status_code == 400  # not classified
    with TestClient(_app(pg_url, oid=VIEWER_OID, roles="viewer")) as c:
        assert c.post(f"/intakes/{mini}/submit", json={}).status_code == 403


def test_full_high_quorum_approves(pg_url):
    intake = _seed_intake(pg_url, "FHQ", tier="high")
    with TestClient(_submitter(pg_url)) as c:
        request_id = c.post(f"/intakes/{intake}/submit", json={}).json()["approval_request_id"]
    gov = _app(pg_url, oid=GOV_OID, roles="business_owner,compliance,legal,model_risk,ai_governance")
    with TestClient(gov) as c:
        result = None
        for _ in range(5):  # each sign-off fills a distinct required-role slot the principal holds
            result = c.post(f"/approvals/{request_id}/signoff", json={"decision_code": "approved"})
            assert result.status_code == 200, result.text
        assert result.json()["status_code"] == "approved"
    with psycopg.connect(pg_url) as conn:
        assert conn.execute(
            "SELECT intake_status_code FROM core.intake WHERE intake_id = %s", (intake,)
        ).fetchone()[0] == "approved"
        # two audited transitions: proposed->in_review (submit) and in_review->approved (resolve)
        assert conn.execute(
            "SELECT count(*) FROM audit.status_transition WHERE entity_id = %s AND entity_type = 'intake'",
            (intake,),
        ).fetchone()[0] == 2


def test_minimal_partial_and_non_required(pg_url):
    high = _seed_intake(pg_url, "HPP", tier="high")
    mini = _seed_intake(pg_url, "MQA", tier="minimal")
    with TestClient(_submitter(pg_url)) as c:
        req_high = c.post(f"/intakes/{high}/submit", json={}).json()["approval_request_id"]
        req_mini = c.post(f"/intakes/{mini}/submit", json={}).json()["approval_request_id"]
    with TestClient(_app(pg_url, oid=BO_OID, roles="business_owner")) as c:
        assert c.post(f"/approvals/{req_high}/signoff", json={"decision_code": "approved"}).json()["status_code"] == "pending"
        assert c.post(f"/approvals/{req_mini}/signoff", json={"decision_code": "approved"}).json()["status_code"] == "approved"
    with TestClient(_app(pg_url, oid=PRIV_OID, roles="privacy")) as c:
        assert c.post(f"/approvals/{req_high}/signoff", json={"decision_code": "approved"}).status_code == 403


def test_self_approval_blocked(pg_url):
    # G1: a business_owner who SUBMITS may not also sign — even though they hold the required role.
    intake = _seed_intake(pg_url, "SLF", tier="minimal")
    bo = _app(pg_url, oid=BO_OID, roles="business_owner")
    with TestClient(bo) as c:
        request_id = c.post(f"/intakes/{intake}/submit", json={}).json()["approval_request_id"]
        assert c.post(f"/approvals/{request_id}/signoff", json={"decision_code": "approved"}).status_code == 403


def test_guards_rejection_duplicate_double_sign_terminal_emptyquorum(pg_url):
    rej = _seed_intake(pg_url, "REJ", tier="minimal")
    dup = _seed_intake(pg_url, "DUP", tier="high")
    dbl = _seed_intake(pg_url, "DBL", tier="high")
    term = _seed_intake(pg_url, "TRM", tier="high", status="rejected")
    unacceptable = _seed_intake(pg_url, "UNA", tier="unacceptable")  # U1: empty quorum
    with TestClient(_submitter(pg_url)) as c:
        req_rej = c.post(f"/intakes/{rej}/submit", json={}).json()["approval_request_id"]
        assert c.post(f"/intakes/{dup}/submit", json={}).status_code == 201
        assert c.post(f"/intakes/{dup}/submit", json={}).status_code == 409  # duplicate open approval
        req_dbl = c.post(f"/intakes/{dbl}/submit", json={}).json()["approval_request_id"]
        assert c.post(f"/intakes/{term}/submit", json={}).status_code == 409  # terminal intake
        assert c.post(f"/intakes/{unacceptable}/submit", json={}).status_code == 409  # empty quorum (U1)
    with TestClient(_app(pg_url, oid=BO_OID, roles="business_owner")) as c:
        assert c.post(f"/approvals/{req_rej}/signoff", json={"decision_code": "rejected"}).json()["status_code"] == "rejected"
        assert c.post(f"/approvals/{req_dbl}/signoff", json={"decision_code": "approved"}).status_code == 200  # 1/5
        assert c.post(f"/approvals/{req_dbl}/signoff", json={"decision_code": "approved"}).status_code == 409  # same slot


def test_requested_changes_closes_request_and_leaves_intake_revisable(pg_url):
    # Parity with application onboarding: a 'requested_changes' sign-off closes the request (no
    # deadlock); the intake stays at in_review so the author can edit & re-submit.
    intake = _seed_intake(pg_url, "RQC", tier="minimal")
    with TestClient(_submitter(pg_url)) as c:
        request_id = c.post(f"/intakes/{intake}/submit", json={}).json()["approval_request_id"]
    with TestClient(_app(pg_url, oid=BO_OID, roles="business_owner")) as c:
        assert c.post(f"/approvals/{request_id}/signoff",
                      json={"decision_code": "requested_changes"}).json()["status_code"] == "rejected"
    with psycopg.connect(pg_url) as conn:
        assert conn.execute(
            "SELECT intake_status_code FROM core.intake WHERE intake_id = %s", (intake,)
        ).fetchone()[0] == "in_review"  # revisable — not moved to a terminal status
