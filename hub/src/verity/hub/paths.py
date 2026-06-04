"""Filesystem anchors resolved by marker, not by parents[N] — robust to package nesting."""
from __future__ import annotations

from pathlib import Path


def _ascend_to(marker: str) -> Path:
    for p in Path(__file__).resolve().parents:
        if (p / marker).exists():
            return p
    raise RuntimeError(f"could not locate '{marker}' above {__file__}")


def component_root() -> Path:
    """The hub/ component directory (holds pyproject.toml, db/, tests/)."""
    return _ascend_to("pyproject.toml")


def repo_root() -> Path:
    """The monorepo root (holds specs/schema/, the canonical schema)."""
    return _ascend_to("specs/schema/verity_schema.sql")
