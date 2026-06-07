"""Pydantic v2 boundary models for application onboarding (US1).

Field names mirror the canonical schema columns (naming gate). The compliance perimeter
(frameworks / domains / jurisdictions) and the three attestations are required (FR-IN-017); the
TLA `code` is validated by shape here and by UNIQUE + CHECK at the DB. Attribution and the
business owner's grant are server-resolved (never client-supplied beyond the named owner id).
"""
from __future__ import annotations

from datetime import datetime
from uuid import UUID

from pydantic import BaseModel, Field


class AppTeamMember(BaseModel):
    actor_id: UUID
    app_team_role_code: str


class ApplicationPropose(BaseModel):
    code: str = Field(pattern=r"^[A-Z]{3}$", description="the TLA")
    name: str = Field(min_length=1)
    description: str = Field(min_length=20)
    line_of_business_code: str | None = None
    data_classification_code: str
    regulatory_framework_codes: list[str] = Field(min_length=1)
    governance_domain_codes: list[str] = Field(min_length=1)
    jurisdiction_codes: list[str] = Field(min_length=1)
    business_owner_actor_id: UUID
    initial_app_team: list[AppTeamMember] = Field(default_factory=list)
    affects_consumers: bool
    processes_pii: bool
    consumer_facing: bool
    justification: str = Field(min_length=1)


class LifecycleChange(BaseModel):
    to_status_code: str  # suspended | retired | active (reactivate)
    reason: str | None = None


class Application(BaseModel):
    application_id: UUID
    code: str
    name: str
    description: str
    application_status_code: str
    line_of_business_code: str | None = None
    data_classification_code: str
    business_owner_actor_id: UUID
    created_by_actor_id: UUID
    regulatory_framework_codes: list[str]
    governance_domain_codes: list[str]
    jurisdiction_codes: list[str]
    affects_consumers: bool
    processes_pii: bool
    consumer_facing: bool
    created_at: datetime
    # latest-approval review status (read-only; from the LATERAL join in get/list, null elsewhere)
    latest_approval_status: str | None = None
    latest_decision: str | None = None
