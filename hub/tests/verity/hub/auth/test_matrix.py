"""Mirrors verity/hub/auth/matrix.py — total coverage + fail-closed gate (FR-008/022/029)."""
from __future__ import annotations

from verity.hub.auth.matrix import ACTION_ROLES, ACTIONS, is_action_allowed


def test_total_coverage_and_fail_closed():
    assert ACTIONS == frozenset(ACTION_ROLES)  # every action has an explicit cell (FR-029)
    assert is_action_allowed({"viewer"}, "view") is True
    assert is_action_allowed({"viewer"}, "grant_platform_role") is False
    assert is_action_allowed({"security"}, "grant_platform_role") is True
    assert is_action_allowed({"engineer"}, "signoff") is False  # FR-022 hard invariant
    assert is_action_allowed({"compliance"}, "signoff") is True
    assert is_action_allowed({"security"}, "no_such_action") is False  # fail-closed
