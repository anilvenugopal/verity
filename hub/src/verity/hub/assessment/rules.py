"""Inherent risk-tier rules (US2, FR-AS-002/008).

A deterministic mapping from the AI-Decision-Impact answers to the intake's **inherent** EU-AI-Act
risk tier + NAIC materiality. "Inherent" = fixed by the use case; never lowered by mitigations
(FR-AS-008). The mapping is intentionally explicit and conservative — when in doubt it rounds up.

Ordered evaluation (first match wins):
  1. unacceptable — an autonomous decision with NO human oversight that unfairly discriminates or
     risks safety for consumers/vulnerable populations (a prohibited pattern under EU-AI-Act framing).
  2. high        — an insurance high-risk domain (underwriting/pricing/claims/fraud) affecting
     consumers/vulnerable with a severe adverse impact (denial / discrimination / safety).
  3. limited     — affects people outside the org, OR is autonomous (transparency/oversight duties).
  4. minimal     — everything else (internal, assistive, low impact).

NAIC materiality is `material` when the tier is high/unacceptable, the use affects consumers, or it
deploys production-wide; otherwise `non_material`.
"""
from __future__ import annotations

from verity.hub.assessment.models import AIDecisionImpact

_INSURANCE_HIGH_RISK_DOMAINS = {"underwriting", "pricing", "claims", "fraud"}
_AFFECTS_PEOPLE = {"policyholders_consumers", "vulnerable"}
_SEVERE_IMPACT = {"coverage_or_claim_denial", "unfair_discriminatory", "safety"}

# The canonical auto-reject note (FR-IN-004).
UNACCEPTABLE_NOTE = (
    "Auto-rejected: AI risk tier 'unacceptable' under EU AI Act framing — prohibited use case."
)


def compute_tier(ai: AIDecisionImpact) -> tuple[str, str]:
    """Return (ai_risk_tier_code, naic_materiality_code)."""
    autonomous = ai.decision_role == "autonomous"
    no_oversight = ai.human_oversight.strategy == "none"
    affects_people = ai.affected_population in _AFFECTS_PEOPLE
    severe = ai.adverse_impact in _SEVERE_IMPACT

    if autonomous and no_oversight and affects_people and ai.adverse_impact in {"unfair_discriminatory", "safety"}:
        tier = "unacceptable"
    elif ai.decision_domain in _INSURANCE_HIGH_RISK_DOMAINS and affects_people and severe:
        tier = "high"
    elif ai.affected_population != "internal_only" or autonomous:
        tier = "limited"
    else:
        tier = "minimal"

    material = (
        tier in {"high", "unacceptable"}
        or affects_people
        or ai.deployment_scale == "production_wide"
    )
    return tier, ("material" if material else "non_material")
