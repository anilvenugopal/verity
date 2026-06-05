"""Pydantic v2 boundary models for the intake assessment (US1 capture; US2/US3 fill `computed`).

The four-tab questionnaire is validated here (required fields per FR-AS-002/003) and stored as
`jsonb`. Answer values are kept as strings (documented choices in the contract) rather than hard
enums, so the questionnaire can evolve without rejecting valid answers; the tier rules (US2) read
named fields. `Computed` is the read-only result (tier/materiality/classification/status).
"""
from __future__ import annotations

from datetime import datetime
from uuid import UUID

from pydantic import BaseModel, Field


class HumanOversight(BaseModel):
    strategy: str  # none | on_the_loop | in_the_loop
    threshold: str | None = None


class AIDecisionImpact(BaseModel):
    decision_role: str  # assists | recommends_with_signoff | autonomous
    decision_domain: str
    affected_population: str  # internal_only | brokers_agents | policyholders_consumers | vulnerable
    adverse_impact: str  # negligible | financial | coverage_or_claim_denial | unfair_discriminatory | safety
    human_oversight: HumanOversight
    reversibility: str
    gdpr_art22: bool
    deployment_scale: str


class DataTab(BaseModel):
    description: str = Field(min_length=1)
    sources: list[str] = Field(default_factory=list)
    data_classification_code: str
    pii_presence: str  # none | direct | indirect | special_category
    sensitive_categories: list[str] = Field(default_factory=list)
    lawful_basis: str | None = None
    residency: str | None = None
    retention: str | None = None
    use: str | None = None


class SecurityAccessTab(BaseModel):
    # Captured for the later access/obligation slices; not resolved here (D-ASM-6).
    sources: list[dict] = Field(default_factory=list)
    targets: list[dict] = Field(default_factory=list)
    tools: list[dict] = Field(default_factory=list)
    credential_handling: str | None = None
    egress: str | None = None


class AssessmentInput(BaseModel):
    ai_decision_impact: AIDecisionImpact
    data: DataTab
    security_access: SecurityAccessTab | None = None
    rationale: str | None = None


class Computed(BaseModel):
    ai_risk_tier_code: str | None = None
    naic_materiality_code: str | None = None
    data_classification_code: str | None = None
    intake_status_code: str | None = None
    auto_rejected: bool = False


class AssessmentView(BaseModel):
    intake_id: UUID
    revision: int
    assessment: dict
    computed: Computed | None = None
    created_at: datetime


class RevisionMeta(BaseModel):
    revision: int
    valid_from: datetime
    valid_to: datetime
    created_by_actor_id: UUID
