# Risk-Tier Mapping — Intake Assessment (rules-mapping)

> ⚠️ **REQUIRES COMPLIANCE / DOMAIN-EXPERT REVIEW BEFORE PRODUCTION USE.**
> This mapping was authored during implementation (Slice 3, `hub/src/verity/hub/assessment/rules.py`)
> as a reasonable, conservative default. It drives the intake's **inherent EU-AI-Act risk tier**
> *and the `unacceptable` auto-reject* — a governance policy decision, not an implementation detail.
> Treat the thresholds below as a **draft policy** pending sign-off by Model Risk / Compliance / Legal.
> (Raised as finding **R1** in /speckit.analyze.)

## Inputs (the AI-Decision-Impact tab — FR-AS-002)
`decision_role`, `decision_domain`, `affected_population`, `adverse_impact`,
`human_oversight.strategy`, `reversibility`, `gdpr_art22`, `deployment_scale`
(all strict enums — A1; an out-of-vocabulary value is rejected 422, never silently down-tiered).

## Current rules (ordered; first match wins)

| Tier | Condition (current draft) |
|---|---|
| **unacceptable** | `decision_role = autonomous` AND `human_oversight.strategy = none` AND `affected_population ∈ {policyholders_consumers, vulnerable}` AND `adverse_impact ∈ {unfair_discriminatory, safety}` |
| **high** | `decision_domain ∈ {underwriting, pricing, claims, fraud}` AND `affected_population ∈ {policyholders_consumers, vulnerable}` AND `adverse_impact ∈ {coverage_or_claim_denial, unfair_discriminatory, safety}` |
| **limited** | `affected_population ≠ internal_only` OR `decision_role = autonomous` |
| **minimal** | everything else |

**NAIC materiality** = `material` when tier ∈ {high, unacceptable}, OR the use affects people
(`policyholders_consumers`/`vulnerable`), OR `deployment_scale = production_wide`; else `non_material`.

**`unacceptable` auto-reject note** (FR-IN-004): *"Auto-rejected: AI risk tier 'unacceptable' under
EU AI Act framing — prohibited use case."*

## Known gaps for the reviewers to decide
- `reversibility` and `gdpr_art22` are **captured but not yet used** in the tier computation — should
  they modify the tier (e.g. GDPR-Art.22 automated decisions → at least `high`)?
- The `unacceptable` definition is intentionally narrow (autonomous + no oversight + discriminatory/safety
  on people). The EU AI Act's *prohibited practices* (social scoring, manipulation, etc.) may need
  explicit additional triggers.
- Materiality is currently boolean-ish; NAIC may want finer gradation.

When this is signed off, fold the agreed rules back into `rules.py` and update this file + research.md D-ASM-3.
