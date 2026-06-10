"""Inherent risk-tier rules (US2, FR-AS-002/008).

A deterministic mapping from the comprehensive assessment to the intake's **inherent** EU-AI-Act risk
tier + NAIC materiality. "Inherent" = fixed by the use case; never lowered by mitigations (FR-AS-008).
The mapping is intentionally explicit and conservative — when in doubt it rounds up. Inputs are the
NAIC five risk dimensions (decision nature, consumer harm, human involvement, transparency, third-
party reliance) layered with the EU Annex III high-risk gate and the special-category-data signal.

Ordered evaluation (first match wins):
  1. unacceptable — fully autonomous with NO effective human oversight (no stop button and no
     overriding control) affecting consumers/vulnerable with a severe consumer effect OR special-
     category data (a prohibited pattern under EU-AI-Act framing).
  2. high        — an EU Annex III high-risk match; OR an insurance decision (underwriting/pricing/
     claims/fraud/eligibility) affecting consumers with a severe effect; OR special-category data on
     a decision affecting people.
  3. limited     — affects people outside the org, OR is autonomous, OR is solely automated (Art 22).
  4. minimal     — everything else (internal, assistive, low impact).

NAIC materiality is `material` when the tier is high/unacceptable, the use affects consumers, or it
deploys production-wide; otherwise `non_material`.
"""
from __future__ import annotations

from verity.hub.assessment.models import AssessmentInput

_INSURANCE_DECISIONS = {"underwriting", "pricing", "claims", "fraud", "eligibility"}
_AFFECTS_PEOPLE = {"policyholders_consumers", "vulnerable"}
_SEVERE_EFFECT = {"coverage_or_eligibility", "claim_denial"}
_AUTONOMOUS = {"conditional_auto", "fully_auto"}

# The canonical auto-reject note (FR-IN-004).
UNACCEPTABLE_NOTE = (
    "Auto-rejected: AI risk tier 'unacceptable' under EU AI Act framing — prohibited use case."
)


def compute_tier(a: AssessmentInput) -> tuple[str, str]:
    """Return (ai_risk_tier_code, naic_materiality_code) from the full assessment."""
    dc, ho = a.decision_context, a.human_oversight
    affects_people = bool(set(dc.affected_populations) & _AFFECTS_PEOPLE)
    severe_effect = dc.consumer_effect in _SEVERE_EFFECT
    autonomous = ho.autonomy_level in _AUTONOMOUS
    # effective oversight = a safe-halt OR at least one control the human can override/reverse with.
    no_oversight = not ho.stop_mechanism and not any(c.can_override for c in ho.controls)
    special_category = any(d.pii_presence == "special_category" for d in a.data_inventory)
    insurance_decision = dc.decision_type in _INSURANCE_DECISIONS

    if ho.autonomy_level == "fully_auto" and no_oversight and affects_people and (severe_effect or special_category):
        tier = "unacceptable"
    elif dc.annex_iii_high_risk or (insurance_decision and affects_people and severe_effect) or (special_category and affects_people):
        tier = "high"
    elif set(dc.affected_populations) != {"internal_only"} or autonomous or dc.solely_automated:
        tier = "limited"
    else:
        tier = "minimal"

    material = (
        tier in {"high", "unacceptable"}
        or affects_people
        or dc.deployment_scale == "production_wide"
    )
    return tier, ("material" if material else "non_material")
