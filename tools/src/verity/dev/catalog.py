"""Predefined dev ops surfaced in the CLI and the menu: queries, test selections, shell ops.
Add a row here and it shows up everywhere — that's the point."""
from __future__ import annotations

# name -> (description, SQL)
QUERIES: dict[str, tuple[str, str]] = {
    "roles": ("platform role vocab", "SELECT code, label FROM reference.role ORDER BY sort_order"),
    "tables": (
        "table counts by schema",
        "SELECT table_schema, count(*) FROM information_schema.tables "
        "WHERE table_schema IN ('reference','core','audit') GROUP BY 1 ORDER BY 1",
    ),
    "auth": (
        "recent auth events",
        "SELECT created_at, event_type, outcome, reason_code, action_code "
        "FROM audit.auth_event ORDER BY created_at DESC LIMIT 20",
    ),
    "actors": ("actors by type", "SELECT actor_type_code, count(*) FROM core.actor GROUP BY 1"),
    "applications": (
        "applications: code, status, owner, classification ceiling",
        "SELECT code, name, application_status_code, data_classification_code, business_owner_actor_id "
        "FROM core.application ORDER BY created_at DESC LIMIT 20",
    ),
    "app_perimeter": (
        "application compliance perimeter (frameworks/domains/jurisdictions)",
        "SELECT a.code, "
        "  (SELECT array_agg(framework_code) FROM core.application_regulatory_framework f WHERE f.application_id=a.application_id) AS frameworks, "
        "  (SELECT array_agg(governance_domain_code) FROM core.application_governance_domain d WHERE d.application_id=a.application_id) AS domains, "
        "  (SELECT array_agg(jurisdiction_code) FROM core.application_jurisdiction j WHERE j.application_id=a.application_id) AS jurisdictions "
        "FROM core.application a ORDER BY a.created_at DESC LIMIT 20",
    ),
    "onboarding_approvals": (
        "application onboarding approvals + status",
        "SELECT r.approval_request_id, app.code, r.status_code, r.created_at "
        "FROM core.approval_request r JOIN core.application app ON app.application_id = r.target_application_id "
        "WHERE r.request_kind_code = 'application_onboarding' ORDER BY r.created_at DESC LIMIT 20",
    ),
    "intakes": (
        "intakes with classification + status",
        "SELECT intake_id, title, intake_status_code, ai_risk_tier_code, naic_materiality_code "
        "FROM core.intake ORDER BY created_at DESC LIMIT 20",
    ),
    "status_history": (
        "intake status transitions (audit)",
        "SELECT created_at, entity_id, from_code, to_code, acting_role_code "
        "FROM audit.status_transition WHERE entity_type = 'intake' ORDER BY created_at DESC LIMIT 20",
    ),
    "requirements": (
        "intake requirements",
        "SELECT intake_requirement_id, intake_id, requirement_kind_code, requirement_status_code, title "
        "FROM core.intake_requirement ORDER BY created_at DESC LIMIT 20",
    ),
    "assessments": (
        "current intake assessments + computed tier/classification/status",
        "SELECT a.intake_id, a.revision, i.ai_risk_tier_code, i.naic_materiality_code, "
        "i.data_classification_code, i.intake_status_code "
        "FROM core.intake_impact_assessment_current a JOIN core.intake i ON i.intake_id = a.intake_id "
        "ORDER BY a.created_at DESC LIMIT 20",
    ),
    "dispatch": (
        "dispatch state",
        "SELECT run_dispatch_status_code, count(*) FROM core.harness_dispatch GROUP BY 1",
    ),
}

# name -> (description, pytest args)
TESTS: dict[str, tuple[str, list[str]]] = {
    "all": ("full suite", ["-q"]),
    "auth": ("auth + app", ["-q", "tests/verity/hub/test_app.py", "tests/verity/hub/auth"]),
    "migrate": ("migrate + reset", ["-q", "tests/verity/hub/test_migrate.py"]),
    "intake": ("intake slice (US1–US4)", ["-q", "tests/verity/hub/intake"]),
}

# name -> (description, argv)
SHELL: dict[str, tuple[str, list[str]]] = {
    "psql": ("open psql on the dev DB", ["docker", "exec", "-it", "verity-dev-pg", "psql", "-U", "postgres", "-d", "verity"]),
    "ps": ("docker ps (verity-dev)", ["docker", "ps", "-a", "--filter", "name=verity-dev-"]),
}
