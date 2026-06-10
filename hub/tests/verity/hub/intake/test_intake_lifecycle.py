"""Pre-approval intake lifecycle (parity with the application onboarding lifecycle): edit-in-place,
withdraw (cancel the open approval), and hard-delete — e2e on PG18 through the mock auth gate.

Mirrors verity/hub/application withdraw/edit/delete: a *revisable* intake (status not in
{approved, in_build, live, retired}) may be edited or deleted; a rejection leaves the intake
revisable (the approval *request* reads 'rejected', the intake stays in_review) so the remediation
loop matches applications. Roles: edit/withdraw need an author (edit_intake); delete needs the app
team (delete_intake = {business_owner, ai_governance, security}); both deny a viewer (FR-029).
"""
from __future__ import annotations

import os

import psycopg
import pytest
from fastapi.testclient import TestClient
from testcontainers.postgres import PostgresContainer

from verity.hub import migrate
from verity.hub.config import get_settings

AUTHOR_OID = "a11c0de0-0000-0000-0000-000000000001"   # engineer: create/edit/withdraw, NOT delete, cannot sign
SEC_OID = "5ec0de00-0000-0000-0000-000000000002"      # security: delete_intake, but NOT an author (no edit)
GOV_OID = "90bce110-0000-0000-0000-000000000003"      # holds the full high quorum (signs)
VIEWER_OID = "11ee0000-0000-0000-0000-000000000004"   # denied everywhere


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


def _author(url):
    return _app(url, oid=AUTHOR_OID, roles="engineer")


def _seed_intake(pg_url, code, tier="high", status="proposed"):
    """Directly seed an active app + an intake with a given tier/status."""
    with psycopg.connect(pg_url, autocommit=True) as conn:
        actor = conn.execute(
            "INSERT INTO core.actor (actor_type_code, display_name) VALUES ('human', %s) RETURNING actor_id",
            (f"{code} actor",),
        ).fetchone()[0]
        app = conn.execute(
            "INSERT INTO core.application (code, name, description, application_status_code, "
            "data_classification_code, business_owner_actor_id, affects_consumers, processes_pii, "
            "consumer_facing, created_by_actor_id, created_role_code) VALUES "
            "(%s, %s, 'x', 'active', 'tier2_internal', %s, false, false, false, %s, 'business_owner') "
            "RETURNING application_id",
            (code, f"{code} app", actor, actor),
        ).fetchone()[0]
        intake = conn.execute(
            "INSERT INTO core.intake (application_id, title, intake_status_code, ai_risk_tier_code, "
            "created_by_actor_id, created_role_code) VALUES (%s, 'Original title', %s, %s, %s, 'business_owner') "
            "RETURNING intake_id",
            (app, status, tier, actor),
        ).fetchone()[0]
    return str(intake)


# ── edit (PUT /intakes/{id}) ─────────────────────────────────────────────────────────────────────

def test_edit_revisable_intake_updates_title_and_description(pg_url):
    intake = _seed_intake(pg_url, "EDT", status="proposed")
    with TestClient(_author(pg_url)) as c:
        r = c.put(f"/intakes/{intake}", json={"title": "Revised title", "description": "Now with detail"})
        assert r.status_code == 200, r.text
        body = r.json()
        assert body["title"] == "Revised title"
        assert body["description"] == "Now with detail"
        assert body["intake_status_code"] == "proposed"  # edit does not move the lifecycle


def test_edit_after_rejection_is_allowed(pg_url):
    # The remediation loop: a quorum rejection leaves the intake at in_review (revisable), so the
    # author can edit and re-submit — exactly like a rejected application stays 'pending'.
    intake = _seed_intake(pg_url, "ERJ", tier="high")
    with TestClient(_author(pg_url)) as c:
        request_id = c.post(f"/intakes/{intake}/submit", json={}).json()["approval_request_id"]
    gov = _app(pg_url, oid=GOV_OID, roles="business_owner,compliance,legal,model_risk,ai_governance")
    with TestClient(gov) as c:
        assert c.post(f"/approvals/{request_id}/signoff", json={"decision_code": "rejected"}).json()["status_code"] == "rejected"
    with TestClient(_author(pg_url)) as c:
        r = c.put(f"/intakes/{intake}", json={"title": "Narrowed scope"})
        assert r.status_code == 200, r.text
        assert r.json()["intake_status_code"] == "in_review"  # still revisable after rejection


def test_edit_locked_intake_is_409(pg_url):
    intake = _seed_intake(pg_url, "ELK", status="approved")
    with TestClient(_author(pg_url)) as c:
        assert c.put(f"/intakes/{intake}", json={"title": "nope"}).status_code == 409


def test_edit_denied_for_viewer(pg_url):
    intake = _seed_intake(pg_url, "EVW", status="proposed")
    with TestClient(_app(pg_url, oid=VIEWER_OID, roles="viewer")) as c:
        assert c.put(f"/intakes/{intake}", json={"title": "nope"}).status_code == 403


# ── withdraw (POST /intakes/{id}/withdraw) ───────────────────────────────────────────────────────

def test_withdraw_cancels_open_approval_and_allows_resubmit(pg_url):
    intake = _seed_intake(pg_url, "WDR", tier="high")
    with TestClient(_author(pg_url)) as c:
        request_id = c.post(f"/intakes/{intake}/submit", json={}).json()["approval_request_id"]
        r = c.post(f"/intakes/{intake}/withdraw", json={})
        assert r.status_code == 200, r.text
        assert r.json()["intake_status_code"] == "in_review"  # status unchanged (mirrors app withdraw)
        # the open request is superseded (cancelled), so a fresh submit is allowed
        assert c.post(f"/intakes/{intake}/submit", json={}).status_code == 201
    with psycopg.connect(pg_url) as conn:
        assert conn.execute(
            "SELECT status_code FROM core.approval_request WHERE approval_request_id = %s", (request_id,)
        ).fetchone()[0] == "cancelled"


def test_withdraw_with_no_open_approval_is_409(pg_url):
    intake = _seed_intake(pg_url, "WNO", status="proposed")  # never submitted
    with TestClient(_author(pg_url)) as c:
        assert c.post(f"/intakes/{intake}/withdraw", json={}).status_code == 409


def test_withdraw_denied_for_viewer(pg_url):
    intake = _seed_intake(pg_url, "WVW", status="proposed")
    with TestClient(_app(pg_url, oid=VIEWER_OID, roles="viewer")) as c:
        assert c.post(f"/intakes/{intake}/withdraw", json={}).status_code == 403


# ── delete (DELETE /intakes/{id}) ────────────────────────────────────────────────────────────────

def test_delete_revisable_intake_cascades_requirements(pg_url):
    intake = _seed_intake(pg_url, "DEL", status="proposed")
    with TestClient(_author(pg_url)) as c:
        assert c.post(f"/intakes/{intake}/requirements",
                      json={"requirement_kind_code": "functional", "title": "R", "body": "b"}).status_code == 201
    with TestClient(_app(pg_url, oid=SEC_OID, roles="security")) as c:
        assert c.delete(f"/intakes/{intake}").status_code == 204
        assert c.get(f"/intakes/{intake}").status_code == 404
    with psycopg.connect(pg_url) as conn:
        assert conn.execute(
            "SELECT count(*) FROM core.intake_requirement WHERE intake_id = %s", (intake,)
        ).fetchone()[0] == 0  # ON DELETE CASCADE


def test_delete_cascades_open_approval_and_signoffs(pg_url):
    intake = _seed_intake(pg_url, "DAP", tier="high")
    with TestClient(_author(pg_url)) as c:
        request_id = c.post(f"/intakes/{intake}/submit", json={}).json()["approval_request_id"]
    gov = _app(pg_url, oid=GOV_OID, roles="business_owner,compliance,legal,model_risk,ai_governance")
    with TestClient(gov) as c:
        assert c.post(f"/approvals/{request_id}/signoff", json={"decision_code": "approved"}).json()["status_code"] == "pending"  # 1/5, still revisable
    with TestClient(_app(pg_url, oid=SEC_OID, roles="security")) as c:
        assert c.delete(f"/intakes/{intake}").status_code == 204
    with psycopg.connect(pg_url) as conn:
        assert conn.execute(
            "SELECT count(*) FROM core.approval_request WHERE target_intake_id = %s", (intake,)
        ).fetchone()[0] == 0
        assert conn.execute(
            "SELECT count(*) FROM core.approval_signoff WHERE approval_request_id = %s", (request_id,)
        ).fetchone()[0] == 0


def test_delete_locked_intake_is_409(pg_url):
    intake = _seed_intake(pg_url, "DLK", status="approved")
    with TestClient(_app(pg_url, oid=SEC_OID, roles="security")) as c:
        assert c.delete(f"/intakes/{intake}").status_code == 409


def test_delete_denied_for_author_without_delete_role(pg_url):
    # An author (engineer) may create/edit but is NOT on the delete_intake cell — fail-closed (FR-029).
    intake = _seed_intake(pg_url, "DNA", status="proposed")
    with TestClient(_author(pg_url)) as c:
        assert c.delete(f"/intakes/{intake}").status_code == 403
    with TestClient(_app(pg_url, oid=VIEWER_OID, roles="viewer")) as c:
        assert c.delete(f"/intakes/{intake}").status_code == 403


def test_unknown_intake_is_404_on_lifecycle(pg_url):
    ghost = "00000000-0000-0000-0000-0000000000ff"
    with TestClient(_author(pg_url)) as c:
        assert c.put(f"/intakes/{ghost}", json={"title": "x"}).status_code == 404
        assert c.post(f"/intakes/{ghost}/withdraw", json={}).status_code == 404
    with TestClient(_app(pg_url, oid=SEC_OID, roles="security")) as c:
        assert c.delete(f"/intakes/{ghost}").status_code == 404
