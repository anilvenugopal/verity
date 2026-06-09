"""Pydantic v2 models for the approval primitive (US2).

`ApprovalRequest` is the read view (kind, status, target, the computed required roles, and the
recorded sign-offs). `Signoff` is the request body for recording a decision; `decision_code` is a
`reference.approval_decision` code (`approved` | `rejected` | `requested_changes` | `abstained`).
"""
from __future__ import annotations

from datetime import datetime
from uuid import UUID

from pydantic import BaseModel


class SubmitForApproval(BaseModel):
    note: str | None = None


class Signoff(BaseModel):
    decision_code: str
    comment: str | None = None


class SignoffRecord(BaseModel):
    approver_actor_id: UUID
    signed_as_role_code: str
    decision_code: str
    comment: str | None = None
    created_at: datetime | None = None


class AwaitingApproval(BaseModel):
    """A row in a principal's MY APPROVALS queue — a pending request they can act on, with the app
    identity to render + link to the workspace."""
    approval_request_id: UUID
    application_id: UUID
    code: str
    name: str


class ApprovalRequest(BaseModel):
    approval_request_id: UUID
    request_kind_code: str
    status_code: str
    target_intake_id: UUID | None = None
    target_application_id: UUID | None = None
    required_roles: list[str]
    signoffs: list[SignoffRecord]
    created_at: datetime
