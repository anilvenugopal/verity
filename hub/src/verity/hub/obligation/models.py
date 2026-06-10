"""Boundary models for intake obligations (003 US1). Status is DERIVED (outstanding/satisfied/
excepted) from evidence + valid exceptions — never stored. Exceptions reuse core.compliance_exception."""
from __future__ import annotations

from datetime import datetime
from uuid import UUID

from pydantic import BaseModel, Field


class ObligationControl(BaseModel):
    control_code: str
    title: str
    control_phase_code: str
    enforcement_action_code: str
    evidence_artifact_type_code: str | None = None
    evidenced: bool


class Obligation(BaseModel):
    intake_obligation_id: UUID
    requirement_code: str
    title: str
    governance_domain_code: str
    target_tier: int
    status: str  # outstanding | satisfied | excepted
    controls: list[ObligationControl] = []


class Rollup(BaseModel):
    total: int
    satisfied: int
    excepted: int
    outstanding: int
    all_resolved: bool


class ObligationSet(BaseModel):
    intake_id: UUID
    obligations: list[Obligation] = []
    rollup: Rollup


class EvidenceInput(BaseModel):
    control_code: str = Field(min_length=1)
    note: str | None = None


class RequirementStatus(BaseModel):
    requirement_code: str
    tier: int
    status: str  # met | outstanding | excepted | not_applicable
    unmet_controls: list[str] = []


class ExceptionInput(BaseModel):
    requirement_code: str = Field(min_length=1)
    waived_tier_level: int = Field(ge=1)
    compensating_controls: str = Field(min_length=1)
    rationale: str = Field(min_length=1)
    expires_at: datetime


class ExceptionView(BaseModel):
    compliance_exception_id: UUID
    canonical_requirement_id: UUID
    waived_tier_level: int
    exception_status_code: str
    expires_at: datetime
    approver_actor_id: UUID | None = None


class ExceptionListItem(BaseModel):
    compliance_exception_id: UUID
    requirement_code: str
    waived_tier_level: int
    exception_status_code: str
    expires_at: datetime
    opened_by_actor_id: UUID
    approver_actor_id: UUID | None = None
    rationale: str
    compensating_controls: str
