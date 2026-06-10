"""Read-only boundary models for the Compliance Model browser (FR-023). Surfaces the governed
metamodel — frameworks → provisions → canonical requirements → cumulative tiers → controls →
evidence — for validation/maintenance. No mutation here (governed editing is a later follow-on)."""
from __future__ import annotations

from pydantic import BaseModel


class Framework(BaseModel):
    framework_code: str
    name: str
    authority: str | None = None
    provision_count: int
    requirement_count: int


class RequirementSummary(BaseModel):
    requirement_code: str
    governance_domain_code: str
    title: str
    frameworks: list[str]
    max_tier: int | None = None
    control_count: int


class EvidenceSpec(BaseModel):
    evidence_artifact_type_code: str
    citable_as: str | None = None


class ControlView(BaseModel):
    control_code: str
    title: str
    control_phase_code: str
    control_type_code: str
    enforcement_action_code: str
    evidence: list[EvidenceSpec] = []


class TierView(BaseModel):
    tier_level: int
    title: str
    criteria: str
    controls: list[ControlView] = []


class ProvisionView(BaseModel):
    framework_code: str
    citation: str
    jurisdiction: str | None = None
    min_tier_level: int


class RequirementDetail(BaseModel):
    requirement_code: str
    governance_domain_code: str
    title: str
    text: str
    provisions: list[ProvisionView] = []
    tiers: list[TierView] = []
