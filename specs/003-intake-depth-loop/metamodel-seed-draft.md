# Compliance Metamodel Seed — REVISED for review (T003)

**Status**: Revised after validation against SR 26-2/SR 11-7, NAIC AI Model Bulletin, NIST AI RMF, EU AI Act, NY DFS CL-7, Colorado SB21-169, GDPR. **Not yet merged.** This is the governed source of truth everything in 003 queries (Principle VIII). On approval it is encoded as `specs/schema/seed/050_compliance_metamodel.sql` + the `051_assessment_requirement_map.sql` triggers.

**28 canonical requirements across all 9 governance domains.** De-duplicated center: one canonical requirement is sourced (by minimum tier) from multiple framework provisions.

## Conventions
- governance_domain ∈ `{model_risk, fairness, privacy, data_governance, human_oversight, transparency, robustness, security, accountability}` — **all nine used**.
- control_phase ∈ `{design_time, deploy_time, static_model, execution}` · control_type ∈ `{preventive, detective, corrective, directive}` · enforcement_action ∈ `{block, refuse, suppress_write, warn, log_only}`.
- evidence_artifact_type ∈ `{document, validation_report, test_result, model_card, decision_log, approval_record, config_snapshot, deployment_record, package_manifest, binding_resolution}`.
- **Tier ladder is cumulative** (tier N ⇒ controls of tiers 1..N). Intake risk tier maps minimal→1, limited→2, high→3.
- **Every control is SMART**: named **actor** · **specific measurable action + numeric threshold/SLA** · **phase** · **cadence/trigger** · **enforcement** · one **typed evidence artifact** so "met?" is a boolean.

## Frameworks (provision sources)
`sr_26_2` (Fed/OCC/FDIC Revised Guidance on Model Risk Management, 2026 — governing; SR 11-7 (2011) is the historical basis) · `naic` (Model Bulletin on the Use of AI Systems by Insurers, 2023; grounded in NIST AI RMF v1.0 + NAIC 2020 AI Principles) · `nist_ai_rmf` (AI RMF 1.0) · `eu_ai_act` (Reg (EU) 2024/1689) · `nydfs` (Circular Letter No. 7, 2024) · `colorado_sb21_169` (C.R.S. § 10-3-1104.9; 3 CCR 702-10 Reg 10-1-1 governance; quantitative-testing life reg is a distinct 3 CCR 702-10 instrument) · `gdpr` (Reg (EU) 2016/679).

> **Citation confidence**: HIGH on EU/GDPR/DFS/Colorado (primary text). NAIC sub-section numbers cited at §-level (AIS Program Guidelines §3 Governance / §4 Risk-Mgmt & Third-Party) — **confirm exact sub-§ against the adopted PDF at encode time**. SR 26-2 supersedes SR 11-7 — **diff numeric thresholds against SR 26-2 text before locking** (structure/effective-challenge carry over).

---

## Domain: model_risk

### `mr-model-risk-rating` — Per-model risk rating selects the control tier
Provisions → sr_26_2 (materiality & complexity commensurate) [T1] · naic §3 (risk-commensurate) [T1]
| Tier | SMART control | Enforce | Evidence |
|---|---|---|---|
| T1 | **Model owner** assigns a per-model risk rating = f(materiality, complexity, breadth-of-use) on a defined scale at **design_time**; the rating selects the applicable T1/T2/T3 set; absent/incorrect rating blocks tier assignment. | block | config_snapshot |

### `mr-model-validation` — Independent validation
Provisions → sr_26_2 (validation: conceptual soundness + ongoing monitoring + outcomes/back-testing) [T1] · naic §4 (validation/testing) [T2] · eu_ai_act Art 9 (risk management) [T2]
| Tier | SMART control | Enforce | Evidence |
|---|---|---|---|
| T1 | **Model owner** authors a model card (intended use, **explicit restrictions on use**, inputs/sources, assumptions, limitations) to a *replicability* standard (a qualified unfamiliar reviewer can reproduce operation), before deploy. | block | model_card |
| T2 | **Independent 2nd-line validator** (no reporting line into dev/business) issues a validation_report covering conceptual soundness, monitoring plan, outcomes-analysis plan, with explicit approve/approve-w-conditions/reject; **deploy prohibited without "approve"**. | block | validation_report |
| T3 | Validator performs a **full refresh ≤12 months and on material change** + benchmarks vs ≥1 challenger; refresh overdue >30 days auto-flags non-compliant. | warn→block | validation_report |

### `mr-effective-challenge` — Independent effective challenge with authority to restrict
Provisions → sr_26_2 (effective challenge: incentives, competence, influence/authority) [T3]
| Tier | SMART control | Enforce | Evidence |
|---|---|---|---|
| T3 | A **2nd-line function organizationally independent of development, with documented authority to restrict/halt model use**, issues an effective-challenge memo per validation cycle; findings tracked to closure before deploy. | block | validation_report |

### `mr-performance-monitoring` — Performance & drift monitoring
Provisions → eu_ai_act Art 72 (post-market monitoring) [T2] · naic §4 (model drift) [T2] · nydfs §II.C ¶17/§III.B ¶26 (regular cadence; ≥annual board review) [T2]
| Tier | SMART control | Enforce | Evidence |
|---|---|---|---|
| T2 | **Model owner** records each performance metric with a **numeric alert + breach threshold** and the action per breach at deploy_time; block deploy if any in-scope metric lacks a numeric threshold. | block | config_snapshot |
| T3 | **First-line MRM** runs automated monitoring (**≥daily for execution-phase models**) + a **drift test ≤12 months or on input-distribution shift**; a breach opens a remediation record within **5 business days**; unremediated > SLA restricts use. | warn→suppress_write | test_result |

### `mr-change-control` — Change management & re-validation trigger
Provisions → sr_26_2 (change control; a variation warranting separate validation) [T2]
| Tier | SMART control | Enforce | Evidence |
|---|---|---|---|
| T2 | **MLOps** version-tracks every change to code/data/parameters; a **material change (per a defined materiality rule) triggers re-validation before redeploy**; an unversioned production change is auto non-compliant (links to FR-IN-013 change proposals). | block | config_snapshot |

---

## Domain: fairness

### `fair-disparate-impact` — Disparate-impact testing
Provisions → nydfs §II.C ¶18 (AIR, SMD, Z/T-tests) [T2] · colorado_sb21_169 §10-3-1104.9 + testing reg [T2] · eu_ai_act Art 10(2)(f-g) (bias examination) [T2]
| Tier | SMART control | Enforce | Evidence |
|---|---|---|---|
| T1 | **Model owner** documents protected classes + rationale for any proxy attributes at design_time. | log_only | document |
| T2 | **Data Science** computes **AIR + SMD** per protected class; **flags AIR < 0.80 or a statistically significant (p<0.05) disparity**; pre-prod + on change + **≥annual**; unresolved breach without an LDA search blocks promotion. | block | test_result |
| T3 | **Less-discriminatory-alternative search performed + documented** + ongoing fairness-metric monitoring at execution. | warn | validation_report |

### `fair-proxy-analysis` — Proxy / correlated-attribute analysis of ECDIS
Provisions → nydfs §II.A ¶12 (proxy assessment of ECDIS) [T2] · colorado_sb21_169 [T2]
| Tier | SMART control | Enforce | Evidence |
|---|---|---|---|
| T2 | **Actuarial/DS** runs a correlation/proxy test of each ECDIS feature vs imputed protected-class status (BISG or equivalent); records the coefficient + retention/removal decision at static_model; no feature enters production without a proxy assessment on file. | block | test_result |

### `fair-fria` — Fundamental-rights impact assessment
Provisions → eu_ai_act Art 27 (FRIA; Annex III 5(c) = life/health insurance → in scope) [T3]
| Tier | SMART control | Enforce | Evidence |
|---|---|---|---|
| T3 | **Compliance** completes the FRIA before first deployment and notifies the market-surveillance authority of the result; recorded reference required. | block | document |

---

## Domain: privacy

### `pr-dpia` — Data-protection impact assessment
Provisions → gdpr Art 35 (DPIA for high-risk processing) [T2]
| Tier | SMART control | Enforce | Evidence |
|---|---|---|---|
| T2 | **DPO** completes a GDPR DPIA before first deploy and records the reference; deployment gate requires the DPIA reference. | block | document |

### `pr-special-category` — Special-category data handling
Provisions → gdpr Art 9 [T2] · eu_ai_act Art 10(5) (special-category for bias monitoring, safeguards) [T2] · *(D3 trigger: assessment `pii_presence=special_category`)*
| Tier | SMART control | Enforce | Evidence |
|---|---|---|---|
| T2 | **DPO** documents lawful basis + safeguards for any special-category data at design_time. | block | document |
| T3 | Minimization + access controls enforced; special-category access logged at execution. | warn | decision_log |

### `pr-data-minimization` — Data minimization & purpose limitation
Provisions → gdpr Art 5(1)(b)(c) [T1]
| Tier | SMART control | Enforce | Evidence |
|---|---|---|---|
| T1 | **DPO** verifies each input feature maps to a documented necessary purpose at design_time and removes features failing the necessity test; feature set frozen only after sign-off. | block | document |

---

## Domain: data_governance

### `dg-data-quality` — Data quality & representativeness
Provisions → eu_ai_act Art 10(2-3) [T1] · naic §4 (data practices: quality, integrity, bias-minimization, suitability) [T2]
| Tier | SMART control | Enforce | Evidence |
|---|---|---|---|
| T1 | **Data owner** documents sources, collection, preparation at design_time. | log_only | document |
| T2 | **Data owner** records representativeness + error/gap assessment + data-bias examination with a pass/fail per check; deploy blocked if any check unrecorded or failed. | block | validation_report |

### `dg-data-provenance` — Provenance & actuarial validity
Provisions → nydfs §II.A (data lifecycle + empirical/actuarial validity, source disclosability) [T2] · eu_ai_act Art 10(2) (origin) [T1] · colorado_sb21_169 (inventory) [T1]
| Tier | SMART control | Enforce | Evidence |
|---|---|---|---|
| T1 | **Data owner** inventories each data source with provenance (internal/third-party/consumer) at design_time. | log_only | document |
| T2 | **Actuarial** demonstrates the empirical/actuarial validity of each data→outcome relationship at static_model. | block | validation_report |

### `dg-record-keeping` — Automatic logging & retention
Provisions → eu_ai_act Art 12 + Art 19 (auto-generated logs) [T1] · eu_ai_act Art 26(6) (deployer log retention ≥6 months) [T1]
| Tier | SMART control | Enforce | Evidence |
|---|---|---|---|
| T1 | **Platform/MLOps** enables automatic event logging over the system lifetime (capability set at deploy_time) and **retains logs ≥6 months**; log-retention config <6mo is a finding. | block | config_snapshot |

---

## Domain: human_oversight

### `ho-human-review` — Effective human oversight
Provisions → eu_ai_act Art 14 (oversight measures) [T1] · eu_ai_act Art 26(2) (deployer assigns competent oversight) [T2]
| Tier | SMART control | Enforce | Evidence |
|---|---|---|---|
| T1 | **Model owner** defines oversight measures (who reviews, what they inspect, override capability) at design_time. | log_only | document |
| T2 | **Underwriting Ops** designates a named competent reviewer with override authority; the system routes any adverse automated decision to that reviewer; the override path is tested at deploy. | block | approval_record |
| T3 | Override/contest events captured + audited at runtime. | warn | decision_log |

### `ho-stop-mechanism` — Safe-halt control
Provisions → eu_ai_act Art 14(4)(e) [T2]
| Tier | SMART control | Enforce | Evidence |
|---|---|---|---|
| T2 | **Model owner** documents a halt/interrupt mechanism at design_time. | block | document |
| T3 | **MLOps** tests the stop mechanism operational in production at deploy_time. | block | test_result |

### `ho-right-to-contest` — Human intervention & contest
Provisions → gdpr Art 22(3) [T2]
| Tier | SMART control | Enforce | Evidence |
|---|---|---|---|
| T2 | **Customer Ops** provides each adversely-affected applicant a contest channel yielding human intervention within a defined SLA (e.g. **30 days**) and logs the outcome at execution; an audited sample must show human review. | warn | decision_log |

---

## Domain: transparency

### `tr-ai-disclosure` — Disclosure that AI/ECDIS is used
Provisions → nydfs §IV.E ¶39 [T1] · eu_ai_act Art 50 (transparency to persons) [T1]
| Tier | SMART control | Enforce | Evidence |
|---|---|---|---|
| T1 | **Customer Ops** prepares a consumer disclosure that AI/ECDIS informs the decision at design_time. | log_only | document |
| T2 | Disclosure delivered + captured (timestamp + applicant id) at each decision; missing-disclosure rate must be 0 in audit. | warn | decision_log |

### `tr-adverse-action` — Adverse-action reasons + data + source
Provisions → nydfs §IV.E ¶39/¶40/¶44 (specific reasons + data + source; **no vendor-proprietary shield**; ≤15 days) [T2]
| Tier | SMART control | Enforce | Evidence |
|---|---|---|---|
| T2 | **Customer Ops** issues adverse-action notices within **15 days** listing specific reasons, the data elements relied on, and each element's source; **may not invoke vendor proprietary nature** to omit specificity; QA samples for source + specificity. | corrective | decision_log |

---

## Domain: security

### `sec-cybersecurity` — Cybersecurity of the AI system
Provisions → eu_ai_act Art 15 (cybersecurity, resilience to attack) [T1]
| Tier | SMART control | Enforce | Evidence |
|---|---|---|---|
| T1 | **Security** records the AI-system threat model + controls (access, adversarial-input resilience, model/data integrity) at design_time; production deploy blocked without a security review on file. | block | document |
| T3 | **Security** runs periodic adversarial/penetration testing (**≤12 months**) of the deployed system. | warn | test_result |

### `sec-incident-reporting` — AI incident detection & reporting
Provisions → eu_ai_act Art 73 (serious-incident reporting; deadlines) [T1] · nist_ai_rmf MANAGE 4.x [T1]
| Tier | SMART control | Enforce | Evidence |
|---|---|---|---|
| T1 | **Incident Mgr** maintains a process to detect, investigate, and report serious AI incidents on the regulatory deadline (e.g. **15 days; 10 days on death; 2 days widespread**) at execution; an unreported in-scope incident is a finding. | corrective | decision_log |

---

## Domain: robustness

### `rob-accuracy-robustness` — Declared accuracy, robustness & resilience
Provisions → eu_ai_act Art 15 (accuracy levels + robustness) [T1] · naic §4 (performance) [T2]
| Tier | SMART control | Enforce | Evidence |
|---|---|---|---|
| T1 | **Model owner** declares accuracy metrics + acceptance levels in the model card at design_time. | block | model_card |
| T2 | **Validation** tests robustness/resilience (e.g. stability under input perturbation, fallback behavior) with a pass criterion at static_model before deploy. | block | validation_report |

---

## Domain: accountability

### `ac-ai-inventory` — Governed AI inventory
Provisions → sr_26_2 (firm-wide inventory + field set) [T1] · naic §3 (inventory) [T1] · colorado_sb21_169 (inventory of ECDIS/models) [T1]
| Tier | SMART control | Enforce | Evidence |
|---|---|---|---|
| T1 | **Accountable owner** registers the model in a firm-wide inventory within **5 business days** of design_time with the mandatory field set (purpose, products, intended use + restrictions, input type/source, owner/validator, last-update, validity window, exceptions); a row missing any mandatory field is non-compliant. | block | config_snapshot |

### `ac-governance-committee` — Board / senior-management governance
Provisions → nydfs §III.B ¶26 (board approves policies ≥annually) [T1] · naic §3 (senior mgmt accountable to board; cross-functional) [T2]
| Tier | SMART control | Enforce | Evidence |
|---|---|---|---|
| T1 | **Board/committee** approves AIS policies at least **annually**; senior management owns day-to-day with defined reporting lines. | log_only | approval_record |
| T2 | A **cross-functional governance committee** (business, actuarial, data science, underwriting/claims, legal, compliance) with a member independent of development records a go/no-go before deploy, reported to the board-accountable executive. | block | approval_record |

### `ac-internal-audit` — Independent internal audit (third line)
Provisions → naic §3 (internal audit function) [T3]
| Tier | SMART control | Enforce | Evidence |
|---|---|---|---|
| T3 | **Internal Audit** independently reviews AIS-Program/MRM compliance **≤12 months** and reports findings to the board committee; overdue audit flags the program non-compliant. | warn | validation_report |

### `ac-qms` — Quality management system
Provisions → eu_ai_act Art 17 (QMS over the AI lifecycle) [T1]
| Tier | SMART control | Enforce | Evidence |
|---|---|---|---|
| T1 | **Compliance** maintains a documented QMS covering the AI lifecycle (design→retirement) with assigned responsibilities; absence blocks high-risk deployment. | block | document |

### `ac-third-party-ai` — Third-party / vendor AI due diligence
Provisions → sr_26_2 (vendor model validation + contingency) [T2] · naic §4 (due diligence + audit rights) [T2] · nydfs §III (vendor mgmt; no proprietary shield) [T2]
| Tier | SMART control | Enforce | Evidence |
|---|---|---|---|
| T2 | **Procurement + Compliance** obtain vendor developmental evidence + intended-use docs, validate the firm's *own use* (sensitivity/benchmark), confirm **contract audit-rights + regulatory-cooperation clause**, and record a contingency plan for vendor unavailability before deploy; a vendor model can't be used in U/W without the diligence package. | block | approval_record |

### `ac-deployer-obligations` — Deployer obligations
Provisions → eu_ai_act Art 26(2)(4)(5)(11) (use per instructions, competent oversight, input representativeness, monitor & inform) [T1]
| Tier | SMART control | Enforce | Evidence |
|---|---|---|---|
| T1 | **Deployer (business owner)** confirms use per provider instructions, competent human oversight assigned, input data representativeness checked, and monitoring + notification duties operational at deploy_time. | block | approval_record |

---

## Assessment → requirement triggers (D3 mapping, seed `051_…`)
| Assessment signal | Triggers requirement (min tier) |
|---|---|
| `decision_context.solely_automated = true` | `ho-human-review` (T2), `ho-right-to-contest` (T2) |
| `data_inventory[*].pii_presence = special_category` | `pr-special-category` (T2), `pr-dpia` (T2) |
| `fairness.disparate_impact_tested` (consumer-facing decision) | `fair-disparate-impact` (T2), `fair-proxy-analysis` (T2) |
| `data_inventory[*].source = third_party` | `ac-third-party-ai` (T2), `dg-data-provenance` (T2) |
| `decision_context.annex_iii_high_risk = true` | `fair-fria` (T3), `ac-qms` (T1), `dg-record-keeping` (T1) |

## Summary & sizing
- **28 canonical requirements** across all **9 domains** (model_risk 5 · fairness 3 · privacy 3 · data_governance 3 · human_oversight 3 · transparency 2 · security 2 · robustness 1 · accountability 6), cumulative T1–T3, controls across all four phases, SMART + verifiable.
- **De-dup confirmed**: shared requirements (disparate-impact, validation, third-party-AI…) are single rows sourced from multiple provisions.
- **Sizing check** — a `high`-tier (T3) consumer-facing claims/underwriting intake in `{model_risk, fairness, privacy, data_governance, human_oversight, transparency, security, robustness, accountability}` resolves to ~**18–22 obligations** across T1–T3 (a realistic full dossier); a `limited` (T2) intake ~10–14; a `minimal` (T1) internal-only intake ~6–8.

## Encode-time checklist (the two locks + SR diff)
1. Confirm the exact **NAIC** sub-§ numbers against the adopted PDF (cited at §3/§4 level here).
2. Confirm the **Colorado** quantitative-testing reg designation (statute `§10-3-1104.9` + governance Reg 10-1-1 are locked; the testing life-reg is a distinct 3 CCR 702-10 instrument).
3. **Diff SR 26-2** numeric expectations vs the SR 11-7 thresholds used here before locking the model_risk controls.
