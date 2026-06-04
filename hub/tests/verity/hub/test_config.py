"""Mirrors verity/hub/config.py — fail-closed startup guardrails (FR-030 / NFR-001a)."""
from __future__ import annotations

import pytest

from verity.hub.config import Settings, validate_startup


def test_mock_in_prod_aborts():
    with pytest.raises(RuntimeError):
        validate_startup(Settings(auth_mode="mock", env="prod"))


def test_mock_in_local_is_allowed():
    validate_startup(Settings(auth_mode="mock", env="local"))  # no raise
