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

DEMO_CODE_PREFIX = "Z"          # demo application TLAs start with Z (the teardown marker)
DEMO_TEAMMATE_NAME = "Devin Shah"   # a synthetic colleague — proposer/owner of the 'awaiting you' app


def _app_id(code: str) -> str:
    """Deterministic application_id per demo code — so refresh recreates the SAME ids and an
    already-open tab's links never 404."""
    return str(uuid.uuid5(uuid.NAMESPACE_DNS, f"verity.demo.application.{code}"))


def _teammate_id() -> str:
    """Deterministic actor_id for the synthetic colleague — lets teardown find it by id rather than
    a visible '[Demo]' tag in the name."""
    return str(uuid.uuid5(uuid.NAMESPACE_DNS, "verity.demo.teammate"))

# Each demo app: who proposes/owns it, what state, and a self-documenting name + description so the
# screen explains what it's demonstrating. owner/proposer ∈ {"you", "team"}.
# state ∈ {"draft", "pending", "rejected"}.
DEMO_APPS = [
    {
        "code": "ZAP", "name": "Life New Business Triage",
        "description": "Screens individual life new-business applications: extracts medical and "
                       "financial disclosures, scores mortality risk, and refers substandard cases to an underwriter.",
        "owner": "team", "proposer": "team", "state": "pending",
        "classification": "tier4_pii_restricted", "frameworks": ["eu_ai_act", "nydfs"],
        "domains": ["model_risk", "fairness", "privacy"], "jurisdictions": ["ny", "ca"],
        "affects_consumers": True, "processes_pii": True, "consumer_facing": False,
    },
    {
        "code": "ZMA", "name": "Personal Auto Underwriting",
        "description": "Extracts risk attributes from personal-auto submissions, scores appetite, and "
                       "routes high-materiality cases to a human underwriter for review.",
        "owner": "you", "proposer": "you", "state": "draft",
        "classification": "tier2_internal", "frameworks": ["internal_only"],
        "domains": ["model_risk"], "jurisdictions": ["us_federal"],
        "affects_consumers": False, "processes_pii": False, "consumer_facing": False,
    },
    {
        "code": "ZMI", "name": "Claims Severity Predictor",
        "description": "Predicts likely claim severity at first notice of loss to prioritise adjuster "
                       "assignment and support early reserve setting.",
        "owner": "you", "proposer": "you", "state": "pending",
        "classification": "tier3_confidential", "frameworks": ["nist_ai_rmf"],
        "domains": ["fairness", "robustness"], "jurisdictions": ["ny"],
        "affects_consumers": True, "processes_pii": False, "consumer_facing": True,
    },
    {
        "code": "ZMR", "name": "Commercial Property Risk Scoring",
        "description": "Scores commercial-property submissions for catastrophe and occupancy risk to "
                       "support quote and decline decisions.",
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
    tid = _teammate_id()
    if not conn.execute("SELECT 1 FROM core.actor WHERE actor_id = %s", (tid,)).fetchone():
        conn.execute(
            "INSERT INTO core.actor (actor_id, actor_type_code, display_name) VALUES (%s,'human',%s)",
            (tid, DEMO_TEAMMATE_NAME),
        )
    return tid


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
    # the synthetic colleague (by deterministic id) + any legacy '[Demo]' actors from older runs
    conn.execute("DELETE FROM core.actor WHERE actor_id = %s OR display_name LIKE %s", (_teammate_id(), "[Demo]%"))
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
            (appr_id, team, "Rejected — the stated purpose is too broad; please narrow the scope and resubmit."),
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
