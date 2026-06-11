"""Pydantic v2 models for change proposals (003 US3).

A change proposal is an `approval_request` with kind `risk_reclassification` or `business_change`,
scoped to a target intake, with impacted executables recorded in `change_proposal_asset`.
"""
from __future__ import annotations

from datetime import datetime
from uuid import UUID

from pydantic import BaseModel

from verity.hub.approval.models import ApprovalRequest, SignoffRecord


class ProposalAsset(BaseModel):
    executable_id: UUID
    name: str
    kind_code: str


class ChangeProposalInput(BaseModel):
    kind_code: str  # risk_reclassification | business_change
    asset_ids: list[UUID] = []  # impacted executables (may be empty)
    note: str | None = None


class ChangeProposalView(ApprovalRequest):
    """The approval view extended with the impacted assets list."""
    assets: list[ProposalAsset] = []


class ForkedVersion(BaseModel):
    """A new draft forked from a champion on proposal approval."""
    executable_id: UUID
    executable_version_id: UUID
    semver: str
