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

import json
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


def _intake_id(code: str) -> str:
    """Deterministic intake_id per demo use-case code — stable across refreshes (same rationale as
    _app_id)."""
    return str(uuid.uuid5(uuid.NAMESPACE_DNS, f"verity.demo.intake.{code}"))

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
    {
        # An ACTIVE application — the governed home that hosts the demo use cases (intakes can only be
        # created under an active app). Owned by you, so its use cases populate MY USE CASES.
        "code": "ZUW", "name": "Underwriting Workbench",
        "description": "The governed home for underwriting AI use cases — a live application hosting "
                       "submission-triage, severity and retention assistants under active oversight.",
        "owner": "you", "proposer": "you", "state": "active",
        "classification": "tier3_confidential", "frameworks": ["nist_ai_rmf", "nydfs"],
        "domains": ["model_risk", "fairness"], "jurisdictions": ["ny", "ca"],
        "affects_consumers": True, "processes_pii": True, "consumer_facing": False,
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
        # use cases first — intake→application is ON DELETE RESTRICT, and intake approvals are too.
        # (requirements + assessment snapshots cascade when the intake row goes.)
        intake_ids = [str(r[0]) for r in conn.execute(
            "SELECT intake_id FROM core.intake WHERE application_id = ANY(%s)", (ids,)
        ).fetchall()]
        if intake_ids:
            conn.execute("DELETE FROM core.approval_signoff WHERE approval_request_id IN "
                         "(SELECT approval_request_id FROM core.approval_request WHERE target_intake_id = ANY(%s))", (intake_ids,))
            conn.execute("DELETE FROM core.approval_request WHERE target_intake_id = ANY(%s)", (intake_ids,))
            conn.execute("DELETE FROM core.intake WHERE intake_id = ANY(%s)", (intake_ids,))
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
    status = "active" if spec["state"] == "active" else "pending"
    conn.execute(
        "INSERT INTO core.application "
        "(application_id, code, name, description, application_status_code, data_classification_code, "
        " business_owner_actor_id, affects_consumers, processes_pii, consumer_facing, "
        " created_by_actor_id, created_role_code) "
        "VALUES (%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s)",
        (app_id, spec["code"], spec["name"], spec["description"], status, spec["classification"], owner,
         spec["affects_consumers"], spec["processes_pii"], spec["consumer_facing"], proposer, role),
    )
    for fw in spec["frameworks"]:
        conn.execute("INSERT INTO core.application_regulatory_framework (application_id, framework_code, created_by_actor_id) VALUES (%s,%s,%s)", (app_id, fw, proposer))
    for dom in spec["domains"]:
        conn.execute("INSERT INTO core.application_governance_domain (application_id, governance_domain_code, created_by_actor_id) VALUES (%s,%s,%s)", (app_id, dom, proposer))
    for jur in spec["jurisdictions"]:
        conn.execute("INSERT INTO core.application_jurisdiction (application_id, jurisdiction_code, created_by_actor_id) VALUES (%s,%s,%s)", (app_id, jur, proposer))

    # draft = never submitted; active = an already-onboarded live app (no open onboarding approval —
    # it hosts use cases instead). Neither carries an onboarding approval_request.
    if spec["state"] in ("draft", "active"):
        return

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


# ── Demo use cases (intakes) under the active 'ZUW' application ──────────────────────────────────
# A spread across the lifecycle. owner ∈ {"you","team"}; status is the intake_status_code; tier/naic/
# mtier/classification are the computed classification (written directly — the seeder bypasses the
# questionnaire but also writes a matching assessment snapshot so the tabs aren't blank). approval ∈
# {None, "pending_you", "pending_team", "approved"}: no approval row / an open kind=intake approval
# opened by you / by the teammate / a closed fully-signed approval.
DEMO_INTAKES = [
    {
        "code": "uc-triage", "title": "New-business submission triage",
        "description": "Reads incoming submissions, extracts key risk attributes, and routes them to the "
                       "right underwriting queue. A fresh draft — not yet assessed.",
        "owner": "you", "status": "proposed",
        "tier": None, "naic": None, "mtier": None, "classification": None, "assess": None, "approval": None,
        "reqs": [
            ("business", "Reduce manual triage time", "Route low-complexity submissions automatically to cut average triage time."),
            ("functional", "Attribute extraction", "Extract line of business, state, and effective date from each submission packet."),
        ],
    },
    {
        "code": "uc-quote-check", "title": "Quote completeness checker",
        "description": "Flags missing or inconsistent fields on a quote before it is bound so underwriters "
                       "fix gaps up front. Assessed (limited) — ready to submit.",
        "owner": "you", "status": "impact_assessment",
        "tier": "limited", "naic": "non_material", "mtier": "medium", "classification": "tier2_internal",
        "assess": dict(decision_type="underwriting", consumer_effect="rate_or_premium", populations=["brokers_agents"],
                       scale="limited", autonomy="recommends_signoff", stop=True,
                       data_name="Quote line items", data_type="tabular", source="internal", pii="none"),
        "approval": None,
        "reqs": [
            ("business", "Fewer bind-time corrections", "Reduce post-bind endorsements caused by missing quote data."),
            ("functional", "Completeness rules", "Check each quote against the required-field set for its product."),
            ("compliance", "Audit trail", "Record every completeness flag and its resolution."),
        ],
    },
    {
        "code": "uc-severity", "title": "Auto claim severity estimator",
        "description": "Predicts likely claim severity at first notice of loss to prioritise adjuster "
                       "assignment. Submitted (high tier) — awaiting the approval quorum.",
        "owner": "you", "status": "in_review",
        "tier": "high", "naic": "material", "mtier": "high", "classification": "tier3_confidential",
        "assess": dict(decision_type="claims", consumer_effect="claim_denial", annex_iii=True,
                       populations=["policyholders_consumers"], scale="production_wide",
                       autonomy="recommends_signoff", stop=True,
                       controls=[{"name": "Adjuster review", "stage": "pre_decision", "responsible_role": "adjuster",
                                  "trigger": "high-severity prediction", "can_override": True, "what_inspected": "severity band + drivers"}],
                       data_name="First-notice-of-loss reports", data_type="document", source="internal", pii="direct",
                       risks=[{"description": "Under-reserving on atypical claims.", "category": "robustness",
                               "likelihood": "possible", "severity": "moderate", "mitigation": "Human review of outliers", "residual": "low"}]),
        "approval": "pending_you",  # you submitted → you cannot sign (separation-of-duty demo)
        "reqs": [
            ("business", "Faster severe-claim response", "Route likely high-severity claims to senior adjusters within the hour."),
            ("functional", "Severity score", "Produce a calibrated severity band per claim at FNOL."),
            ("non_functional", "Latency", "Return a score within 2 seconds of FNOL intake."),
        ],
    },
    {
        "code": "uc-retention", "title": "Renewal retention scorer",
        "description": "Scores renewing policies for lapse risk so servicing can intervene early. "
                       "Submitted by a teammate (limited tier) — awaiting YOUR sign-off.",
        "owner": "team", "status": "in_review",
        "tier": "limited", "naic": "non_material", "mtier": "medium", "classification": "tier2_internal",
        "assess": dict(decision_type="servicing", consumer_effect="marketing_only", populations=["policyholders_consumers"],
                       scale="limited", autonomy="recommends_review", stop=True,
                       data_name="Renewal & engagement history", data_type="tabular", source="internal", pii="indirect"),
        "approval": "pending_team",  # teammate submitted → you (AI Governance) can approve it
        "reqs": [
            ("business", "Improve retention", "Surface at-risk renewals in time for a servicing outreach."),
            ("functional", "Lapse-risk score", "Score every renewing policy 30 days before expiry."),
        ],
    },
    {
        "code": "uc-doc-classify", "title": "Policy document classifier",
        "description": "Sorts inbound policy documents by type to speed routing. Fully approved (minimal "
                       "tier) — a completed, locked use case.",
        "owner": "you", "status": "approved",
        "tier": "minimal", "naic": "non_material", "mtier": "low", "classification": "tier2_internal",
        "assess": dict(decision_type="internal_ops", consumer_effect="none", populations=["internal_only"],
                       scale="pilot", autonomy="assists", stop=True,
                       data_name="Scanned policy documents", data_type="document", source="internal", pii="none"),
        "approval": "approved",  # opened by you, signed off by the teammate as business_owner
        "reqs": [
            ("business", "Faster document routing", "Cut manual sorting of inbound policy documents."),
            ("functional", "Document type", "Classify each document into one of the known policy-document types."),
        ],
    },
]


def _assess_json(a: dict, classification: str) -> str:
    """Build a full assessment snapshot (the comprehensive AssessmentInput shape the portal reads) from
    compact params, so an assessed demo intake shows a filled sectioned assessment."""
    return json.dumps({
        "decision_context": {
            "decision_type": a["decision_type"], "consumer_effect": a["consumer_effect"],
            "annex_iii_high_risk": a.get("annex_iii", False), "solely_automated": a.get("solely", False),
            "affected_populations": a["populations"], "deployment_scale": a["scale"],
        },
        "data_inventory": [
            {"name": a["data_name"], "direction": "input", "data_type": a.get("data_type", "document"),
             "source": a.get("source", "internal"), "classification": classification, "pii_presence": a["pii"],
             "lawful_basis": a.get("lawful_basis"), "retention": a.get("retention")},
        ],
        "human_oversight": {
            "autonomy_level": a["autonomy"], "stop_mechanism": a.get("stop", True),
            "controls": a.get("controls", []),
        },
        "risks": a.get("risks", []),
        "fairness": a.get("fairness", {"disparate_impact_tested": False, "protected_classes_tested": [], "metrics": []}),
    })


def _create_intake(conn, app_id: str, spec: dict, you: str, team: str) -> None:
    creator = you if spec["owner"] == "you" else team
    role = _ROLE[spec["owner"]]
    iid = _intake_id(spec["code"])  # stable across refreshes
    conn.execute(
        "INSERT INTO core.intake "
        "(intake_id, application_id, title, description, intake_status_code, ai_risk_tier_code, "
        " naic_materiality_code, materiality_tier_code, data_classification_code, created_by_actor_id, created_role_code) "
        "VALUES (%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s)",
        (iid, app_id, spec["title"], spec["description"], spec["status"], spec["tier"],
         spec["naic"], spec["mtier"], spec["classification"], creator, role),
    )
    for kind, title, body in spec["reqs"]:
        conn.execute(
            "INSERT INTO core.intake_requirement (intake_id, requirement_kind_code, title, body, created_by_actor_id, created_role_code) "
            "VALUES (%s,%s,%s,%s,%s,%s)",
            (iid, kind, title, body, creator, role),
        )
    if spec["assess"]:
        conn.execute(
            "INSERT INTO core.intake_impact_assessment (intake_id, revision, assessment, created_by_actor_id, created_role_code) "
            "VALUES (%s, 1, %s, %s, %s)",
            (iid, _assess_json(spec["assess"], spec["classification"]), creator, role),
        )
    appr = spec["approval"]
    if appr:
        opener = team if appr == "pending_team" else creator
        opener_role = "ai_governance" if opener == you else "business_owner"
        status = "approved" if appr == "approved" else "pending"
        appr_id = str(conn.execute(
            "INSERT INTO core.approval_request (request_kind_code, target_intake_id, opened_by_actor_id, opened_role_code, status_code) "
            "VALUES ('intake', %s, %s, %s, %s) RETURNING approval_request_id",
            (iid, opener, opener_role, status),
        ).fetchone()[0])
        if appr == "approved":
            # minimal-tier quorum = [business_owner]; the teammate signs (≠ the opener — separation of duty)
            conn.execute(
                "INSERT INTO core.approval_signoff (approval_request_id, approver_actor_id, signed_as_role_code, decision_code, comment) "
                "VALUES (%s,%s,'business_owner','approved',%s)",
                (appr_id, team, "Approved — low-risk internal classifier."),
            )


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

        # use cases (intakes) under the active ZUW application (exists after the loop above)
        zuw_id = _app_id("ZUW")
        existing_intakes = {str(r[0]) for r in conn.execute(
            "SELECT intake_id FROM core.intake WHERE application_id = %s", (zuw_id,)
        ).fetchall()}
        for ispec in DEMO_INTAKES:
            if _intake_id(ispec["code"]) in existing_intakes:
                out.append(f"    use case '{ispec['title']}' — exists, skipped")
                continue
            _create_intake(conn, zuw_id, ispec, you_id, team)
            created += 1
            out.append(f"    use case '{ispec['title']}' ({ispec['status']}) — created")

        conn.commit()
        out.append(f"done: {created} created, {len(existing)} skipped")
    return out
