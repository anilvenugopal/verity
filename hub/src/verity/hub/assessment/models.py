"""Pydantic v2 boundary models for the intake assessment (US1 capture; US2/US3 fill `computed`).

Comprehensive sectioned model (A+B+C+D redesign — data-model §10), grounded in EU AI Act (Art 9/10/
14/27, Annex III), NIST AI RMF (MAP/MEASURE), the NAIC Model Bulletin's five risk dimensions, NY DFS
CL-7, Colorado SB21-169 and GDPR Art 22. ONE assessment stored as a single jsonb snapshot (SCD-2);
**data**, **human-oversight controls**, **risks** and **fairness metrics** are multi-entry inventories.
Tier-driving answers are strict `Literal` enums (A1: an out-of-vocabulary value MUST 422 rather than
silently fall through compute_tier to a lower tier). `Computed` is the read-only result.
"""
from __future__ import annotations

from datetime import datetime
from typing import Literal
from uuid import UUID

from pydantic import BaseModel, Field

# ── Section A — Decision context (mostly tier-driving) ────────────────────────────────────────────
class DecisionContext(BaseModel):
    decision_type: Literal["underwriting", "pricing", "claims", "fraud", "marketing", "servicing", "eligibility", "internal_ops"]
    consumer_effect: Literal["none", "marketing_only", "rate_or_premium", "coverage_or_eligibility", "claim_denial"]
    annex_iii_high_risk: bool
    solely_automated: bool
    affected_populations: list[Literal["internal_only", "brokers_agents", "policyholders_consumers", "vulnerable"]] = Field(min_length=1)
    deployment_scale: Literal["pilot", "limited", "production_wide"]


# ── Section B — Data inventory (multi-entry; EU Art 10 / OECD) ────────────────────────────────────
class DataItem(BaseModel):
    name: str = Field(min_length=1)
    direction: Literal["input", "output"]
    data_type: Literal["tabular", "text", "image", "audio", "document", "derived"]
    source: Literal["internal", "third_party", "consumer_provided", "public", "synthetic", "system_generated"]
    classification: str  # reference.data_classification code (validated at capture, derived to intake level)
    pii_presence: Literal["none", "indirect", "direct", "special_category"]
    lawful_basis: str | None = None
    retention: str | None = None
    notes: str | None = None


# ── Section C — Human oversight (autonomy classifier + multi-entry measures; EU Art 14) ───────────
class OversightControl(BaseModel):
    name: str = Field(min_length=1)
    stage: Literal["pre_decision", "real_time", "post_hoc", "exception", "troubleshooting"]
    responsible_role: str = Field(min_length=1)
    trigger: str | None = None
    can_override: bool = False
    what_inspected: str | None = None


class HumanOversight(BaseModel):
    autonomy_level: Literal["assists", "recommends_review", "recommends_signoff", "conditional_auto", "fully_auto"]
    stop_mechanism: bool = False
    controls: list[OversightControl] = Field(default_factory=list)


# ── Section D — Risks (multi-entry; EU Art 9 / ICO register) & Fairness (NY DFS / CO SB21-169) ────
class RiskItem(BaseModel):
    description: str = Field(min_length=1)
    category: Literal["fairness", "privacy", "safety", "transparency", "robustness", "security", "financial"]
    likelihood: Literal["rare", "possible", "likely", "almost_certain"]
    severity: Literal["minor", "moderate", "major", "severe"]
    mitigation: str | None = None
    residual: Literal["low", "medium", "high"] | None = None


class FairnessMetric(BaseModel):
    name: str = Field(min_length=1)
    group: str | None = None
    value: str | None = None


class Fairness(BaseModel):
    disparate_impact_tested: bool = False
    protected_classes_tested: list[str] = Field(default_factory=list)
    metrics: list[FairnessMetric] = Field(default_factory=list)
    less_discriminatory_alternative: str | None = None


class AssessmentInput(BaseModel):
    decision_context: DecisionContext
    data_inventory: list[DataItem] = Field(min_length=1)
    human_oversight: HumanOversight
    risks: list[RiskItem] = Field(default_factory=list)
    fairness: Fairness | None = None
    data_governance_narrative: str | None = None
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
