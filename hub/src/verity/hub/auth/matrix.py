"""The action-permission matrix and the fail-closed action gate (FR-008, FR-009, FR-029).

NOTE: the exact allowed-role cells must be ported VERBATIM from v1 web/middleware/persona.py
`_ACTION_ROLES` (legacy is read-only — reference, never import). The structure below is correct
and fail-closed; `test_matrix_total_coverage` asserts every action has an explicit cell. Treat
the cell contents as provisional until reconciled against v1.
"""
from __future__ import annotations

# The 10 platform roles (reference.role) — carried verbatim from v1 studio_role.
PLATFORM_ROLES: frozenset[str] = frozenset({
    "business_owner", "compliance", "legal", "model_risk", "ai_governance",
    "security", "privacy", "engineer", "auditor", "viewer",
})

# The 7 approval-capable roles (FR-009). Enforced independently of the matrix (FR-022).
APPROVAL_ROLES: frozenset[str] = frozenset({
    "business_owner", "compliance", "legal", "model_risk", "ai_governance", "security", "privacy",
})

_AUTHORS = frozenset({"engineer", "ai_governance", "business_owner"})
_GOVERNANCE = APPROVAL_ROLES

# action_code -> allowed platform roles. Absent action => deny (FR-029).
ACTION_ROLES: dict[str, frozenset[str]] = {
    # read
    "view": PLATFORM_ROLES,
    "view_reports": PLATFORM_ROLES,
    # intake authoring / lifecycle
    "onboard_application": frozenset({"business_owner", "ai_governance", "security"}),
    "create_intake": _AUTHORS,
    "edit_intake": _AUTHORS,
    "triage_intake": _GOVERNANCE,
    "reclassify_risk": _GOVERNANCE,
    "edit_requirement": _AUTHORS,
    "edit_impact_assessment": _GOVERNANCE,
    "generate_plan": _AUTHORS,
    "edit_plan": _AUTHORS,
    "edit_plan_estimate": _AUTHORS,
    "edit_roi_assessment": _AUTHORS | {"business_owner"},
    "realize_plan": _AUTHORS,
    "lock_envelope": frozenset({"business_owner", "ai_governance"}),
    # approvals (FR-009 subset; also FR-022 hard invariant)
    "signoff": APPROVAL_ROLES,
    "withdraw_approval": APPROVAL_ROLES,
    # registry
    "author_registry": frozenset({"engineer", "ai_governance"}),
    "promote_registry": frozenset({"engineer", "ai_governance", "business_owner"}),
    "export_yaml": frozenset({"engineer", "ai_governance"}),
    "import_yaml": frozenset({"engineer", "ai_governance"}),
    # role mutation (FR-023) — platform-role mutation is security-only
    "grant_platform_role": frozenset({"security"}),
    "revoke_platform_role": frozenset({"security"}),
    # app-team mutation: security here; app-scoped owner/lead checked separately (FR-023)
    "grant_app_team_role": frozenset({"security"}),
    "revoke_app_team_role": frozenset({"security"}),
}

# The complete set of declared actions (drives the FR-029 coverage check).
ACTIONS: frozenset[str] = frozenset(ACTION_ROLES)


def is_action_allowed(roles: set[str], action: str) -> bool:
    """Fail-closed (FR-008): unknown action, or no role overlap, => deny."""
    allowed = ACTION_ROLES.get(action)
    if allowed is None:
        return False
    # Hard invariant (FR-022): approval actions require an approval-subset role regardless.
    if action in {"signoff", "withdraw_approval"} and not (roles & APPROVAL_ROLES):
        return False
    return bool(roles & allowed)


def acting_role_for(roles: set[str], action: str) -> str:
    """The role the principal acts under for an authorized action: a held role that permits it
    (deterministic). Only meaningful after is_action_allowed() is true; falls back defensively."""
    matched = sorted(roles & ACTION_ROLES.get(action, frozenset()))
    if matched:
        return matched[0]
    return sorted(roles)[0] if roles else "viewer"
