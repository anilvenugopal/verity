"""Demo / test-data seeder — for TESTING & DEMONSTRATIONS ONLY.

Direct SQL against the dev database, entirely separate from the governed reference/core seed in
specs/schema/seed/ (different level of governance + maintenance). Every row it writes is tagged so it
can only ever touch its own data:
  - applications use TLA codes starting with 'Z' (ZAP / ZMA / ZMI / ZMR)
  - the synthetic teammate actor is named '[Demo] Teammate'

"You" is resolved to your real (Entra) account so the apps you "create" show up under MY APPLICATIONS.
States are produced by writing the same rows the app would (application + perimeter + approval +
sign-off), so the portal reads them exactly like real data. Nothing here is ever shipped or seeded
into prod — it lives only in the dev tool.
"""
from __future__ import annotations

import uuid

import psycopg

DEMO_CODE_PREFIX = "Z"          # demo application TLAs start with Z
DEMO_TEAMMATE = "[Demo] Teammate"


def _app_id(code: str) -> str:
    """Deterministic application_id per demo code — so refresh recreates the SAME ids and an
    already-open tab's links never 404."""
    return str(uuid.uuid5(uuid.NAMESPACE_DNS, f"verity.demo.application.{code}"))

# Each demo app: who proposes/owns it, what state, and a self-documenting name + description so the
# screen explains what it's demonstrating. owner/proposer ∈ {"you", "team"}.
# state ∈ {"draft", "pending", "rejected"}.
DEMO_APPS = [
    {
        "code": "ZAP", "name": "[Demo] Awaiting your approval",
        "description": "A teammate submitted this and it needs your AI-Governance sign-off — this is "
                       "how a request appears in MY APPROVALS. Open it and Approve / Request changes / Reject.",
        "owner": "team", "proposer": "team", "state": "pending",
        "classification": "tier4_pii_restricted", "frameworks": ["eu_ai_act", "nydfs"],
        "domains": ["model_risk", "fairness", "privacy"], "jurisdictions": ["ny", "ca"],
        "affects_consumers": True, "processes_pii": True, "consumer_facing": False,
    },
    {
        "code": "ZMA", "name": "[Demo] My draft application",
        "description": "Created by you and not yet submitted — this is how a Draft appears in "
                       "MY APPLICATIONS. Edit it and Submit for approval when ready.",
        "owner": "you", "proposer": "you", "state": "draft",
        "classification": "tier2_internal", "frameworks": ["internal_only"],
        "domains": ["model_risk"], "jurisdictions": ["us_federal"],
        "affects_consumers": False, "processes_pii": False, "consumer_facing": False,
    },
    {
        "code": "ZMI", "name": "[Demo] My application in review",
        "description": "Created by you and submitted — this is how an In-review application appears in "
                       "MY APPLICATIONS while its approval is pending.",
        "owner": "you", "proposer": "you", "state": "pending",
        "classification": "tier3_confidential", "frameworks": ["nist_ai_rmf"],
        "domains": ["fairness", "robustness"], "jurisdictions": ["ny"],
        "affects_consumers": True, "processes_pii": False, "consumer_facing": True,
    },
    {
        "code": "ZMR", "name": "[Demo] My rejected application",
        "description": "Created by you, submitted, and a teammate rejected it — this is how a Rejected "
                       "application appears in MY APPLICATIONS. Use Edit & re-submit to remediate.",
        "owner": "you", "proposer": "you", "state": "rejected",
        "classification": "tier3_confidential", "frameworks": ["colorado_sb21_169"],
        "domains": ["fairness", "transparency"], "jurisdictions": ["co"],
        "affects_consumers": True, "processes_pii": False, "consumer_facing": False,
    },
]

_ROLE = {"you": "ai_governance", "team": "business_owner"}  # the capacity each acts in


def _resolve_you(conn) -> tuple[str, str] | None:
    """Your real (Entra) actor — the most recent human account that ISN'T a mock login. Mock logins
    are all provisioned with email 'dev@localhost', so excluding that picks the real Entra user.
    Returns (actor_id, display_name)."""
    row = conn.execute(
        "SELECT au.actor_id, ac.display_name "
        "FROM core.account_user au JOIN core.actor ac ON ac.actor_id = au.actor_id "
        "WHERE au.email IS DISTINCT FROM 'dev@localhost' "
        "ORDER BY au.created_at DESC LIMIT 1"
    ).fetchone()
    return (str(row[0]), row[1]) if row else None


def _ensure_teammate(conn) -> str:
    row = conn.execute("SELECT actor_id FROM core.actor WHERE display_name = %s", (DEMO_TEAMMATE,)).fetchone()
    if row:
        return str(row[0])
    row = conn.execute(
        "INSERT INTO core.actor (actor_type_code, display_name) VALUES ('human', %s) RETURNING actor_id",
        (DEMO_TEAMMATE,),
    ).fetchone()
    return str(row[0])


def teardown(conn) -> int:
    """Remove every demo row (apps + their dependents + the demo teammate). Returns apps removed."""
    ids = [str(r[0]) for r in conn.execute(
        "SELECT application_id FROM core.application WHERE code LIKE %s", (DEMO_CODE_PREFIX + "%",)
    ).fetchall()]
    if ids:
        conn.execute("DELETE FROM core.approval_signoff WHERE approval_request_id IN "
                     "(SELECT approval_request_id FROM core.approval_request WHERE target_application_id = ANY(%s))", (ids,))
        conn.execute("DELETE FROM core.approval_request WHERE target_application_id = ANY(%s)", (ids,))
        conn.execute("DELETE FROM core.application_regulatory_framework WHERE application_id = ANY(%s)", (ids,))
        conn.execute("DELETE FROM core.application_governance_domain WHERE application_id = ANY(%s)", (ids,))
        conn.execute("DELETE FROM core.application_jurisdiction WHERE application_id = ANY(%s)", (ids,))
        conn.execute("DELETE FROM core.actor_app_role_grant WHERE application_id = ANY(%s)", (ids,))
        conn.execute("DELETE FROM core.application WHERE application_id = ANY(%s)", (ids,))
    conn.execute("DELETE FROM core.actor WHERE display_name LIKE %s", ("[Demo]%",))
    return len(ids)


def _create(conn, spec: dict, you: str, team: str) -> None:
    owner = you if spec["owner"] == "you" else team
    proposer = you if spec["proposer"] == "you" else team
    role = _ROLE[spec["proposer"]]
    app_id = _app_id(spec["code"])  # stable across refreshes
    conn.execute(
        "INSERT INTO core.application "
        "(application_id, code, name, description, application_status_code, data_classification_code, "
        " business_owner_actor_id, affects_consumers, processes_pii, consumer_facing, "
        " created_by_actor_id, created_role_code) "
        "VALUES (%s,%s,%s,%s,'pending',%s,%s,%s,%s,%s,%s,%s)",
        (app_id, spec["code"], spec["name"], spec["description"], spec["classification"], owner,
         spec["affects_consumers"], spec["processes_pii"], spec["consumer_facing"], proposer, role),
    )
    for fw in spec["frameworks"]:
        conn.execute("INSERT INTO core.application_regulatory_framework (application_id, framework_code, created_by_actor_id) VALUES (%s,%s,%s)", (app_id, fw, proposer))
    for dom in spec["domains"]:
        conn.execute("INSERT INTO core.application_governance_domain (application_id, governance_domain_code, created_by_actor_id) VALUES (%s,%s,%s)", (app_id, dom, proposer))
    for jur in spec["jurisdictions"]:
        conn.execute("INSERT INTO core.application_jurisdiction (application_id, jurisdiction_code, created_by_actor_id) VALUES (%s,%s,%s)", (app_id, jur, proposer))

    if spec["state"] == "draft":
        return  # no approval — a Draft

    appr_id = str(conn.execute(
        "INSERT INTO core.approval_request (request_kind_code, target_application_id, opened_by_actor_id, opened_role_code, status_code) "
        "VALUES ('application_onboarding', %s, %s, %s, 'pending') RETURNING approval_request_id",
        (app_id, proposer, role),
    ).fetchone()[0])

    if spec["state"] == "rejected":
        # a teammate rejects it as AI Governance → request closed 'rejected'; the app stays pending so
        # it can be remediated (Edit & re-submit).
        conn.execute(
            "INSERT INTO core.approval_signoff (approval_request_id, approver_actor_id, signed_as_role_code, decision_code, comment) "
            "VALUES (%s,%s,'ai_governance','rejected',%s)",
            (appr_id, team, "[demo] Rejected — the stated purpose is too broad; narrow the scope and resubmit."),
        )
        conn.execute("UPDATE core.approval_request SET status_code = 'rejected' WHERE approval_request_id = %s", (appr_id,))
    # state == "pending": leave the approval open (In review / Awaiting your approval)


def run(db_url: str, mode: str) -> list[str]:
    """mode ∈ {"idempotent", "refresh"}. Returns human-readable summary lines."""
    out: list[str] = []
    with psycopg.connect(db_url, autocommit=False) as conn:
        you = _resolve_you(conn)
        if you is None:
            return ["No Entra account found — sign in via Entra once (so your account exists), then re-run."]
        you_id, you_name = you
        out.append(f"demo owner = {you_name}")

        if mode == "refresh":
            removed = teardown(conn)
            out.append(f"refresh: removed {removed} existing demo app(s)")

        team = _ensure_teammate(conn)
        existing = {r[0] for r in conn.execute(
            "SELECT code FROM core.application WHERE code LIKE %s", (DEMO_CODE_PREFIX + "%",)
        ).fetchall()}
        created = 0
        for spec in DEMO_APPS:
            if spec["code"] in existing:
                out.append(f"  {spec['code']} {spec['name']} — exists, skipped")
                continue
            _create(conn, spec, you_id, team)
            created += 1
            out.append(f"  {spec['code']} {spec['name']} — created")
        conn.commit()
        out.append(f"done: {created} created, {len(existing)} skipped")
    return out
