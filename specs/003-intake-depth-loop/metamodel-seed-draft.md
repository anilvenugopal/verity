# Compliance Metamodel Seed — DRAFT for review (T003)

**Status**: DRAFT — author-grounded, **not yet merged**. This is the governed source of truth everything in 003 queries (Principle VIII). Review the **content** (requirements, tier criteria, controls, evidence, citations); on approval it is encoded as `specs/schema/seed/050_compliance_metamodel.sql`.

**Conventions** (all key onto verified reference codes):
- governance_domain ∈ `{model_risk, fairness, privacy, data_governance, human_oversight, transparency, robustness, security, accountability}`
- control_phase ∈ `{design_time, deploy_time, static_model, execution}` · control_type ∈ `{preventive, detective, corrective, directive}` · enforcement_action ∈ `{block, refuse, suppress_write, warn, log_only}`
- evidence_artifact_type ∈ `{document, validation_report, test_result, model_card, decision_log, approval_record, config_snapshot, deployment_record, …}`
- **Tier ladder is cumulative**: tier N pulls in the controls of tiers 1..N. Intake risk tier maps minimal→1, limited→2, high→3.
- **Citations marked `[verify]`** are ones I want you to confirm against the source text before merge (examiners rely on these).

**Frameworks referenced** (provision sources): `eu_ai_act`, `nydfs` (DFS CL-7, 2024), `colorado_sb21_169` (+ DOI ECDIS regs), `naic` (Model Bulletin on AI, 2023), `gdpr`. *(NAIC + GDPR framework codes may need adding to `reference.regulatory_framework` — flagged in T003.)*

> **The de-duplication principle to confirm**: each canonical requirement below is a **single normalized center** that multiple framework provisions map onto (by minimum tier) — not per-framework copies. E.g. `fair-disparate-impact` is one requirement sourced from EU + NY + CO provisions.

---

## Domain: fairness

### `fair-disparate-impact` — Disparate-impact testing of consumer outcomes
**Provisions →** EU AI Act Art 10(2)(f)–(g) [min T2] · NY DFS CL-7 (quantitative testing / unfair discrimination) [min T2] `[verify §]` · Colorado SB21-169 + DOI ECDIS reg (testing for unfair discrimination) [min T2] `[verify reg cite]`
| Tier | Criteria | Control (phase/type) | Evidence |
|---|---|---|---|
| T1 | Protected classes + rationale for any proxy attributes documented | design_time / directive | document |
| T2 | Quantitative disparate-impact test run (e.g. Adverse Impact Ratio, SMD) with results | static_model / detective | test_result, validation_report |
| T3 | Less-discriminatory-alternative analysis performed + ongoing fairness-metric monitoring | design_time / detective (LDA) · execution / detective (drift) | validation_report, decision_log |

### `fair-proxy-analysis` — Proxy / correlated-attribute analysis
**Provisions →** NY DFS CL-7 (proxy analysis of ECDIS) [min T2] `[verify]` · Colorado SB21-169 [min T2]
| Tier | Criteria | Control | Evidence |
|---|---|---|---|
| T2 | Inputs analyzed for correlation with protected classes; high-proxy features justified or removed | static_model / detective | test_result |
| T3 | Proxy analysis re-run on each material model change + monitored | execution / detective | decision_log |

---

## Domain: model_risk

### `mr-model-validation` — Independent model validation
**Provisions →** NAIC Model Bulletin §4 (model validation / oversight) [min T1] `[verify §]` · EU AI Act Art 9 (risk-management system) [min T2] · (SR 11-7 model-risk practice — reference, not a regulatory provision row) `[verify whether to cite]`
| Tier | Criteria | Control | Evidence |
|---|---|---|---|
| T1 | Model purpose, assumptions, limitations documented (model card) | design_time / directive | model_card, document |
| T2 | Independent validation of conceptual soundness + outcome testing before deploy | deploy_time / preventive (block) | validation_report |
| T3 | Validation refreshed on material change + benchmark/challenger comparison | static_model / detective | validation_report |

### `mr-performance-monitoring` — Ongoing performance & drift monitoring
**Provisions →** EU AI Act Art 72 (post-market monitoring) [min T2] `[verify Art]` · NAIC Model Bulletin (ongoing monitoring) [min T2] · NY DFS CL-7 (at least annual drift testing) [min T2] `[verify]`
| Tier | Criteria | Control | Evidence |
|---|---|---|---|
| T2 | Performance metrics + thresholds defined; monitoring plan in place | design_time / directive | document |
| T3 | Continuous metric monitoring with alerting; ≥ annual drift test | execution / detective (warn) | decision_log, test_result |

---

## Domain: data_governance

### `dg-data-quality` — Training/validation/test data quality & representativeness
**Provisions →** EU AI Act Art 10(2)–(3) (data governance, quality, representativeness) [min T1]
| Tier | Criteria | Control | Evidence |
|---|---|---|---|
| T1 | Data sources, collection, preparation documented | design_time / directive | document |
| T2 | Representativeness + error/gap assessment; bias examination of data | static_model / detective | validation_report |
| T3 | Data-quality checks enforced at each refresh | execution / detective | test_result |

### `dg-data-provenance` — Data provenance & actuarial validity
**Provisions →** NY DFS CL-7 (data lifecycle + actuarial/empirical validity, source disclosability) [min T2] `[verify]` · Colorado SB21-169 (data inventory) [min T1] · EU AI Act Art 10(2) (origin) [min T1]
| Tier | Criteria | Control | Evidence |
|---|---|---|---|
| T1 | Each data source inventoried with provenance (internal/third-party/consumer) | design_time / directive | document |
| T2 | Empirical/actuarial validity of each data→outcome relationship demonstrated | static_model / detective | validation_report |

---

## Domain: privacy

### `pr-dpia` — Data-protection impact assessment
**Provisions →** GDPR Art 35 (DPIA for high-risk processing) [min T2] · EU AI Act Art 27 (FRIA, conditional) [min T3] `[verify scope]`
| Tier | Criteria | Control | Evidence |
|---|---|---|---|
| T2 | DPIA completed + reference recorded when personal data drives consequential decisions | deploy_time / preventive | document, approval_record |
| T3 | Fundamental-rights impact assessment (FRIA) where the deployer/category requires it | design_time / directive | document |

### `pr-special-category` — Special-category data handling
**Provisions →** GDPR Art 9 (special categories) [min T2] · EU AI Act Art 10(5) (special-category processing for bias monitoring, safeguards) [min T2]
| Tier | Criteria | Control | Evidence |
|---|---|---|---|
| T2 | Lawful basis + safeguards for any special-category data documented | design_time / preventive | document |
| T3 | Minimization + access controls enforced; processing logged | execution / detective | decision_log |
*(Triggered by assessment `pii_presence = special_category` — D3 mapping.)*

---

## Domain: human_oversight

### `ho-human-review` — Effective human oversight & right to intervention
**Provisions →** EU AI Act Art 14 (human oversight measures) [min T1] · GDPR Art 22(3) (right to obtain human intervention) [min T2]
| Tier | Criteria | Control | Evidence |
|---|---|---|---|
| T1 | Oversight measures defined: who reviews, what they inspect, override capability | design_time / directive | document |
| T2 | Human review/override demonstrably available for consequential automated decisions | deploy_time / preventive | approval_record |
| T3 | Override/contest events captured + audited at runtime | execution / detective | decision_log |
*(Triggered by `solely_automated = true` — D3 mapping.)*

### `ho-stop-mechanism` — Safe-halt / stop control
**Provisions →** EU AI Act Art 14(4)(e) (stop button) [min T2]
| Tier | Criteria | Control | Evidence |
|---|---|---|---|
| T2 | A documented mechanism to halt/interrupt the system exists | design_time / preventive | document |
| T3 | Stop mechanism tested + operational in production | deploy_time / preventive (block) | test_result |

---

## Domain: transparency

### `tr-ai-disclosure` — Disclosure that AI/ECDIS is used
**Provisions →** NY DFS CL-7 (consumer disclosure of AIS/ECDIS use) [min T1] `[verify]` · EU AI Act Art 13/52 (transparency to users) [min T1] `[verify Art]`
| Tier | Criteria | Control | Evidence |
|---|---|---|---|
| T1 | Consumer-facing disclosure that AI/ECDIS informs the decision is prepared | design_time / directive | document |
| T2 | Disclosure delivered at the decision point | execution / directive (log_only) | decision_log |

### `tr-adverse-action` — Adverse-action reason + data + source
**Provisions →** NY DFS CL-7 (adverse action: specific reasons, data, source; no vendor-proprietary shield) [min T2] `[verify]`
| Tier | Criteria | Control | Evidence |
|---|---|---|---|
| T2 | Adverse-action notices give specific reasons + the data elements + their source | execution / corrective | decision_log |

---

## Domain: accountability

### `ac-ai-inventory` — Governed AI inventory & program oversight
**Provisions →** NAIC Model Bulletin (AIS program, governance, inventory) [min T1] · Colorado SB21-169 (inventory of ECDIS/models) [min T1]
| Tier | Criteria | Control | Evidence |
|---|---|---|---|
| T1 | The use case is recorded in the governed AI inventory with an accountable owner | design_time / directive | approval_record |
| T2 | Cross-functional governance review documented before deployment | deploy_time / preventive | approval_record |

---

## Summary for review

- **13 canonical requirements** across 7 domains; cumulative T1–T3 ladders; controls spread across all four phases; evidence keyed to real artifact types.
- **De-dup center confirmed**: shared requirements (disparate-impact, validation, DPIA…) are single rows sourced from multiple framework provisions.
- **D3 assessment triggers** wired to: `fair-disparate-impact` (disparate_impact answer), `pr-special-category` (special_category), `ho-human-review` (solely_automated).
- **Sizing check** against the demo intakes: a `high`-tier claims/underwriting intake in domains `{model_risk, fairness}` (e.g. *Auto claim severity estimator*) resolves to ~6–8 obligations across T1–T3 — a realistic, non-trivial set.

### Please review / correct
1. **The de-dup principle** (one canonical center, many provisions) — confirm.
2. **The citations marked `[verify]`** — correct any section/article numbers (I'd rather under-claim than mis-cite).
3. **Coverage** — any domain/requirement you want added or dropped for the curated starter.
4. **Tier assignments** (which tier a provision's minimum is, and what each tier demands) — these drive who-gets-what.

On your sign-off I encode this verbatim into `050_compliance_metamodel.sql` (+ the `051_assessment_requirement_map.sql` triggers) as T003.
