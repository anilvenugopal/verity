"""Feature 005 integration tests: entity registration, composition, champion promotion,
bindings, model catalog, and YAML round-trip. Runs against a real PG18 container."""
from __future__ import annotations

import os
import time

import psycopg
import pytest
from fastapi.testclient import TestClient
from testcontainers.postgres import PostgresContainer

from verity.hub import migrate
from verity.hub.config import get_settings

ENG_OID = "aaaa1111-2222-3333-4444-555566667777"


def _seed_app(pg_url, code):
    with psycopg.connect(pg_url, autocommit=True) as conn:
        owner = conn.execute(
            "INSERT INTO core.actor (actor_type_code, display_name) VALUES ('human', %s) RETURNING actor_id",
            (f"{code} owner",),
        ).fetchone()[0]
        app_id = conn.execute(
            "INSERT INTO core.application (code, name, description, application_status_code, "
            "data_classification_code, business_owner_actor_id, affects_consumers, processes_pii, "
            "consumer_facing, created_by_actor_id, created_role_code) "
            "VALUES (%s,%s,'test','active','tier3_confidential',%s,true,false,false,%s,'business_owner') "
            "RETURNING application_id",
            (code, f"{code} App", owner, owner),
        ).fetchone()[0]
        return str(app_id)


@pytest.fixture(scope="module")
def pg_url():
    with PostgresContainer("pgvector/pgvector:pg18", username="postgres", password="postgres", dbname="verity") as pg:
        url = pg.get_connection_url().replace("+psycopg2", "")
        os.environ.update(VERITY_DATABASE_URL=url, VERITY_ENV="local", VERITY_AUTH_MODE="mock")
        get_settings.cache_clear()
        migrate.run()
        yield url


@pytest.fixture(scope="module")
def app_id(pg_url):
    return _seed_app(pg_url, "YRL")


@pytest.fixture(scope="module")
def client(pg_url):
    os.environ.update(
        VERITY_DATABASE_URL=pg_url, VERITY_ENV="local", VERITY_AUTH_MODE="mock",
        VERITY_MOCK_MICROSOFT_OID=ENG_OID,
        VERITY_MOCK_PLATFORM_ROLES="engineer,ai_governance,business_owner",
    )
    get_settings.cache_clear()
    from verity.hub.app import create_app
    with TestClient(create_app()) as c:
        yield c


# ── (1) Register executable + duplicate name rejection ────────────────────────

def test_register_executable_and_duplicate(client):
    r = client.post("/executables", json={"name": "test-agent-005", "display_name": "Test Agent 005", "kind_code": "agent"})
    assert r.status_code == 201
    assert r.json()["kind_code"] == "agent"
    r2 = client.post("/executables", json={"name": "test-agent-005", "display_name": "Test Agent 005", "kind_code": "agent"})
    assert r2.status_code == 409


# ── (2) Create prompt version + content hash present ─────────────────────────

def test_create_prompt_version_content_hash(client):
    p = client.post("/prompts", json={"name": "uw-system-prompt-005", "display_name": "UW System Prompt 005"}).json()
    assert "prompt_id" in p
    blocks = [{"id": "s1", "kind": "prose", "text": "You are an underwriting assistant."}]
    pv = client.post(f"/prompts/{p['prompt_id']}/versions",
                      json={"semver": "1.0.0", "blocks": blocks}).json()
    assert pv["content_hash"] != ""
    assert pv["semver"] == "1.0.0"


# ── (3) Create agent version with governance fields ───────────────────────────

def test_create_agent_version_governance_fields(client):
    ex = client.post("/executables", json={"name": "governed-agent-005", "display_name": "Governed Agent 005", "kind_code": "agent"}).json()
    body = {
        "semver": "1.0.0",
        "governance_tier_code": "contextual",
        "capability_type_code": "classification",
        "trust_level_code": "conditional",
    }
    vr = client.post(f"/executables/{ex['executable_id']}/versions", json=body).json()
    assert vr["semver"] == "1.0.0"
    assert vr["governance_tier_code"] == "contextual"


# ── (4) Assign tool to agent version succeeds ─────────────────────────────────

def test_assign_tool_to_agent(client):
    ex = client.post("/executables", json={"name": "tool-agent-005", "display_name": "Tool Agent 005", "kind_code": "agent"}).json()
    v = client.post(f"/executables/{ex['executable_id']}/versions",
                     json={"semver": "1.0.0"}).json()
    t = client.post("/tools", json={"name": "lookup-tool-005", "display_name": "Lookup Tool 005", "transport_code": "http"}).json()
    tv = client.post(f"/tools/{t['tool_id']}/versions",
                      json={"semver": "1.0.0"}).json()
    r = client.post(f"/versions/{v['executable_version_id']}/tool-assignments",
                     json={"tool_version_id": tv["tool_version_id"]})
    assert r.status_code == 201
    assignments = client.get(f"/versions/{v['executable_version_id']}/tool-assignments").json()
    assert any(a["tool_version_id"] == tv["tool_version_id"] for a in assignments)


# ── (5) Assign tool to task version returns 409 ───────────────────────────────

def test_assign_tool_to_task_returns_409(client):
    task = client.post("/executables", json={"name": "task-no-tools-005", "display_name": "Task No Tools 005", "kind_code": "task"}).json()
    tv_task = client.post(f"/executables/{task['executable_id']}/versions",
                           json={"semver": "1.0.0"}).json()
    t = client.post("/tools", json={"name": "agent-only-tool-005", "display_name": "Agent Only Tool 005", "transport_code": "http"}).json()
    tv = client.post(f"/tools/{t['tool_id']}/versions", json={"semver": "1.0.0"}).json()
    r = client.post(f"/versions/{tv_task['executable_version_id']}/tool-assignments",
                     json={"tool_version_id": tv["tool_version_id"]})
    assert r.status_code == 409


# ── (6) Promote v1 to champion ────────────────────────────────────────────────

def test_promote_v1_to_champion(client):
    ex = client.post("/executables", json={"name": "champ-agent-005", "display_name": "Champ Agent 005", "kind_code": "agent"}).json()
    v1 = client.post(f"/executables/{ex['executable_id']}/versions",
                      json={"semver": "1.0.0"}).json()
    p = client.post("/prompts", json={"name": "champ-prompt-005", "display_name": "Champ Prompt 005"}).json()
    pv = client.post(f"/prompts/{p['prompt_id']}/versions",
                      json={"semver": "1.0.0", "blocks": [{"id": "s1", "kind": "prose", "text": "hello"}]}).json()
    client.post(f"/versions/{v1['executable_version_id']}/prompt-assignments",
                 json={"prompt_version_id": pv["prompt_version_id"], "api_role_code": "system"})
    r = client.post(f"/versions/{v1['executable_version_id']}/promote")
    assert r.status_code == 200
    champion = client.get(f"/executables/{ex['executable_id']}/champion").json()
    assert champion["executable_version_id"] == v1["executable_version_id"]


# ── (7) Promote v2 atomically — only v2 is champion ──────────────────────────

def test_promote_v2_replaces_v1(client):
    ex = client.post("/executables", json={"name": "champ2-agent-005", "display_name": "Champ2 Agent 005", "kind_code": "agent"}).json()
    v1 = client.post(f"/executables/{ex['executable_id']}/versions",
                      json={"semver": "1.0.0"}).json()
    p = client.post("/prompts", json={"name": "champ2-prompt-005", "display_name": "Champ2 Prompt 005"}).json()
    pv = client.post(f"/prompts/{p['prompt_id']}/versions",
                      json={"semver": "1.0.0", "blocks": [{"id": "s1", "kind": "prose", "text": "hi"}]}).json()
    client.post(f"/versions/{v1['executable_version_id']}/prompt-assignments",
                 json={"prompt_version_id": pv["prompt_version_id"], "api_role_code": "system"})
    before_v2 = time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime())
    client.post(f"/versions/{v1['executable_version_id']}/promote")

    v2 = client.post(f"/executables/{ex['executable_id']}/versions",
                      json={"semver": "2.0.0"}).json()
    client.post(f"/versions/{v2['executable_version_id']}/prompt-assignments",
                 json={"prompt_version_id": pv["prompt_version_id"], "api_role_code": "system"})
    client.post(f"/versions/{v2['executable_version_id']}/promote")

    champion = client.get(f"/executables/{ex['executable_id']}/champion").json()
    assert champion["executable_version_id"] == v2["executable_version_id"]


# ── (8) GET champion?as_of=<before v2 promote> returns v1 ────────────────────

def test_champion_as_of(client):
    ex = client.post("/executables", json={"name": "asof-agent-005", "display_name": "Asof Agent 005", "kind_code": "agent"}).json()
    v1 = client.post(f"/executables/{ex['executable_id']}/versions",
                      json={"semver": "1.0.0"}).json()
    p = client.post("/prompts", json={"name": "asof-prompt-005", "display_name": "Asof Prompt 005"}).json()
    pv = client.post(f"/prompts/{p['prompt_id']}/versions",
                      json={"semver": "1.0.0", "blocks": [{"id": "s1", "kind": "prose", "text": "x"}]}).json()
    client.post(f"/versions/{v1['executable_version_id']}/prompt-assignments",
                 json={"prompt_version_id": pv["prompt_version_id"], "api_role_code": "system"})
    client.post(f"/versions/{v1['executable_version_id']}/promote")
    time.sleep(1)  # ensure snapshot is strictly after v1's clock_timestamp()

    snapshot = time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime())
    time.sleep(1)  # ensure v2 promotion is strictly after snapshot

    v2 = client.post(f"/executables/{ex['executable_id']}/versions",
                      json={"semver": "2.0.0"}).json()
    client.post(f"/versions/{v2['executable_version_id']}/prompt-assignments",
                 json={"prompt_version_id": pv["prompt_version_id"], "api_role_code": "system"})
    client.post(f"/versions/{v2['executable_version_id']}/promote")

    r = client.get(f"/executables/{ex['executable_id']}/champion", params={"as_of": snapshot})
    assert r.status_code == 200
    assert r.json()["executable_version_id"] == v1["executable_version_id"]


# ── (9) storage_object source binding without connector_version_id → 422 ─────

def test_storage_object_source_binding_422(client):
    ex = client.post("/executables", json={"name": "binding-agent-005", "display_name": "Binding Agent 005", "kind_code": "agent"}).json()
    v = client.post(f"/executables/{ex['executable_id']}/versions",
                     json={"semver": "1.0.0"}).json()
    r = client.post(f"/versions/{v['executable_version_id']}/source-bindings", json={
        "name": "input-docs",
        "source_kind_code": "storage_object",
        "delivery_mode_code": "reference",
    })
    assert r.status_code == 422


# ── (10) Register model + set price + rebind model reference ──────────────────

def test_model_catalog(client):
    m = client.post("/models", json={"model_code": "claude-test-005", "provider": "anthropic"}).json()
    assert m["model_status_code"] == "active"

    price = client.post(f"/models/{m['model_id']}/prices",
                         json={"input_price_per_1k": 0.003, "output_price_per_1k": 0.015}).json()
    assert float(price["input_price_per_1k"]) == 0.003

    models = client.get("/models").json()
    our_model = next((x for x in models if x["model_code"] == "claude-test-005"), None)
    assert our_model is not None
    assert our_model["current_price"] is not None

    ref = client.post("/model-references", json={
        "reference_code": "test-primary-005", "name": "Test Primary 005",
    }).json()
    binding = client.post(f"/model-references/{ref['model_reference_id']}/bindings",
                           json={"model_id": m["model_id"]}).json()
    assert "model_reference_binding_id" in binding

    m2 = client.post("/models", json={"model_code": "claude-test-v2-005", "provider": "anthropic"}).json()
    rebind = client.post(f"/model-references/{ref['model_reference_id']}/bindings",
                          json={"model_id": m2["model_id"], "reason": "upgrade"}).json()
    assert "model_reference_binding_id" in rebind

    refs = client.get("/model-references").json()
    our_ref = next((r for r in refs if r["reference_code"] == "test-primary-005"), None)
    assert our_ref is not None
    assert our_ref["current_model_code"] == "claude-test-v2-005"


# ── (11) YAML round-trip: export → dry-run import → all no_op ────────────────

def test_yaml_round_trip(client, app_id):
    ex = client.post("/executables", json={"name": "yaml-agent-005", "display_name": "YAML Agent 005", "kind_code": "agent", "application_id": app_id}).json()
    v = client.post(f"/executables/{ex['executable_id']}/versions",
                     json={"semver": "1.0.0"}).json()
    vid = v["executable_version_id"]

    p = client.post("/prompts", json={"name": "yaml-prompt-005", "display_name": "YAML Prompt 005", "application_id": app_id}).json()
    pv = client.post(f"/prompts/{p['prompt_id']}/versions",
                      json={"semver": "1.0.0", "blocks": [{"id": "s1", "kind": "prose", "text": "export test"}]}).json()
    client.post(f"/versions/{vid}/prompt-assignments",
                 json={"prompt_version_id": pv["prompt_version_id"], "api_role_code": "system"})

    export_r = client.get(f"/versions/{vid}/export")
    assert export_r.status_code == 200
    yaml_content = export_r.content

    dry_run_r = client.post(
        "/import/dry-run",
        content=yaml_content,
        headers={"Content-Type": "application/x-yaml"},
    )
    assert dry_run_r.status_code == 200
    report = dry_run_r.json()
    assert report["created"] == 0
    assert report["no_op"] > 0


# ── (12) Where-used returns entries after assignment ──────────────────────────

def test_where_used_prompt_version(client):
    p = client.post("/prompts", json={"name": "used-prompt-005", "display_name": "Used Prompt 005"}).json()
    pv = client.post(f"/prompts/{p['prompt_id']}/versions",
                      json={"semver": "1.0.0", "blocks": [{"id": "s1", "kind": "prose", "text": "used"}]}).json()

    ex = client.post("/executables", json={"name": "user-agent-005", "display_name": "User Agent 005", "kind_code": "agent"}).json()
    v = client.post(f"/executables/{ex['executable_id']}/versions",
                     json={"semver": "1.0.0"}).json()

    empty = client.get(f"/prompt-versions/{pv['prompt_version_id']}/used-by").json()
    assert empty == []

    client.post(f"/versions/{v['executable_version_id']}/prompt-assignments",
                 json={"prompt_version_id": pv["prompt_version_id"], "api_role_code": "system"})

    used_by = client.get(f"/prompt-versions/{pv['prompt_version_id']}/used-by").json()
    assert any(u["executable_version_id"] == v["executable_version_id"] for u in used_by)
