-- =====================================================================
-- seed/core_seed.sql — Verity v2 core data-driven config (seed)
-- Apply AFTER verity_schema.sql + reference_seed.sql. Idempotent. ADR-0011/0006.
-- =====================================================================

INSERT INTO core.lifecycle_deployment_rule (lifecycle_state_code, environment_kind_code, allowed_run_modes, output_suppressed) VALUES
    ('staging',   'non_prod',  ARRAY['live'],            false),
    ('challenger','prod',      ARRAY['shadow','ab'],     false),
    ('challenger','ephemeral', ARRAY['shadow','ab'],     false),
    ('champion',  'prod',      ARRAY['live'],            false),
    ('champion',  'non_prod',  ARRAY['live'],            false),
    ('champion',  'ephemeral', ARRAY['live','shadow'],   false),
    ('deprecated','prod',      ARRAY['locked'],          true),
    ('deprecated','ephemeral', ARRAY['locked','shadow'], true)
    ON CONFLICT (lifecycle_state_code, environment_kind_code) DO NOTHING;

-- Regulatory frameworks an application may declare in scope (FR-IN-017). Starter set; extensible.
-- 'internal_only' / 'nist_ai_rmf' serve as the explicit "no external regime" sentinels (D-ONB).
INSERT INTO core.regulatory_framework (framework_code, name, authority) VALUES
    ('nist_ai_rmf','NIST AI Risk Management Framework','NIST'),
    ('naic_model_bulletin_ai','NAIC Model Bulletin on the Use of AI Systems by Insurers','NAIC'),
    ('colorado_sb21_169','Colorado SB21-169 (Insurance Anti-Discrimination)','Colorado DOI'),
    ('eu_ai_act','EU AI Act','European Union'),
    ('nydfs','NYDFS guidance','NY Dept of Financial Services'),
    ('iso_42001','ISO/IEC 42001 (AI Management System)','ISO/IEC'),
    ('internal_only','Internal governance only (no external regime)','Internal')
    ON CONFLICT (framework_code) DO NOTHING;

-- -------------------------------------------------------------------------
-- Model catalog seed (ADR-0019 / design decision D10)
-- Standard Anthropic models, stable logical references, and initial bindings.
-- Apply AFTER reference_seed.sql (reference.model_status, reference.role,
-- reference.actor_type must exist).
-- -------------------------------------------------------------------------

-- Bootstrap automation actor for seed-time operations (NULL created_by_actor_id
-- is the only valid nil; see core.actor schema comment).
INSERT INTO core.actor (actor_id, actor_type_code, display_name, primary_role_code, created_by_actor_id) VALUES
    ('00000000-0000-0000-0000-000000000001'::uuid, 'automation', 'Verity Seed', 'ai_governance', NULL)
    ON CONFLICT (actor_id) DO NOTHING;

-- Provider models (current Anthropic Claude 4 family)
INSERT INTO core.model (model_code, provider, modality, model_status_code) VALUES
    ('claude-opus-4-8',   'anthropic', 'chat', 'active'),
    ('claude-sonnet-4-6', 'anthropic', 'chat', 'active'),
    ('claude-haiku-4-5',  'anthropic', 'chat', 'active')
    ON CONFLICT (model_code) DO NOTHING;

-- Standard logical model references (stable aliases; executables point at these,
-- not at concrete model strings — see ADR-0019 and design decision D10).
INSERT INTO core.model_reference (reference_code, name, description) VALUES
    ('reasoning-primary',     'Reasoning Primary',      'Default for agentic / assessment tasks'),
    ('reasoning-fallback',    'Reasoning Fallback',     'Fallback for reasoning tasks'),
    ('extraction-primary',    'Extraction Primary',     'Lighter tasks, higher throughput'),
    ('extraction-fallback',   'Extraction Fallback',    'Fallback for extraction tasks'),
    ('classification-primary','Classification Primary', 'Classification, low-latency')
    ON CONFLICT (reference_code) DO NOTHING;

-- Initial model_reference_binding rows — one open SCD-2 window per reference.
-- Operators close and re-open these via POST /api/registry/model-references/:id/bind
-- without requiring re-promotion of any executable.
INSERT INTO core.model_reference_binding
    (model_reference_id, model_id, valid_from, valid_to, reason, bound_by_actor_id, bound_role_code)
SELECT
    mr.model_reference_id,
    m.model_id,
    now(),
    '2099-12-31 00:00:00+00'::timestamptz,
    'initial seed',
    '00000000-0000-0000-0000-000000000001'::uuid,
    'ai_governance'
FROM (VALUES
    ('reasoning-primary',     'claude-opus-4-8'),
    ('reasoning-fallback',    'claude-sonnet-4-6'),
    ('extraction-primary',    'claude-sonnet-4-6'),
    ('extraction-fallback',   'claude-haiku-4-5'),
    ('classification-primary','claude-haiku-4-5')
) AS seed(ref_code, model_code)
JOIN core.model_reference mr ON mr.reference_code = seed.ref_code
JOIN core.model            m  ON m.model_code      = seed.model_code
ON CONFLICT DO NOTHING;

-- Initial model prices (open SCD-2 window). Input/output per 1k tokens, USD.
-- These are June 2025 list prices; operators update via POST /api/registry/models/:id/prices.
INSERT INTO core.model_price (model_id, input_price_per_1k, output_price_per_1k, currency_code)
SELECT m.model_id, seed.input_p, seed.output_p, 'usd'
FROM (VALUES
    ('claude-opus-4-8',   15.00,  75.00),
    ('claude-sonnet-4-6',  3.00,  15.00),
    ('claude-haiku-4-5',   0.80,   4.00)
) AS seed(model_code, input_p, output_p)
JOIN core.model m ON m.model_code = seed.model_code
WHERE NOT EXISTS (
    SELECT 1 FROM core.model_price p
    WHERE p.model_id = m.model_id AND p.valid_to = '2099-12-31 00:00:00+00'
);

-- =========================================================================
-- Compliance metamodel (feature 003, T003) — governed source of truth.
-- Provisions → canonical requirements → tier ladders → controls → evidence.
-- 28 canonical requirements across all governance domains. Idempotent.
-- Citations validated (SR 26-2 governing; EU Art 50; CO §10-3-1104.9).
-- =========================================================================
SET search_path TO core, reference, public;

-- Extra frameworks not in the starter set above
INSERT INTO core.regulatory_framework (framework_code, name, authority) VALUES
  ('gdpr',   'General Data Protection Regulation (EU) 2016/679', 'European Union'),
  ('sr_26_2','Revised Guidance on Model Risk Management (SR 26-2; basis SR 11-7)', 'Federal Reserve / OCC / FDIC')
ON CONFLICT (framework_code) DO NOTHING;

-- Regulatory provisions (citable sources)
INSERT INTO core.regulatory_provision (provision_code, framework_code, citation, jurisdiction, text)
SELECT v.code, v.fw, v.cite, v.juris, v.txt FROM (VALUES
  ('sr262-validation','sr_26_2','SR 26-2 (basis SR 11-7) — Model Validation','US','Three core elements: conceptual soundness, ongoing monitoring, outcomes analysis/back-testing.'),
  ('sr262-challenge','sr_26_2','SR 26-2 (basis SR 11-7) — Effective Challenge','US','Critical analysis by objective, informed parties with authority to restrict model use.'),
  ('sr262-inventory','sr_26_2','SR 26-2 (basis SR 11-7) — Model Inventory','US','Firm-wide inventory with purpose, restrictions on use, validity window, validation dates.'),
  ('sr262-change','sr_26_2','SR 26-2 (basis SR 11-7) — Change Control','US','Rigorous change control; a variation warranting separate validation is a separate model.'),
  ('sr262-rating','sr_26_2','SR 26-2 (basis SR 11-7) — Risk-Commensurate Rigor','US','Validation rigor commensurate with materiality and complexity of model risk.'),
  ('sr262-vendor','sr_26_2','SR 26-2 (basis SR 11-7) — Vendor/Third-Party Models','US','Validate own use of vendor products; obtain developmental evidence; contingency plans.'),
  ('naic-validation','naic_model_bulletin_ai','NAIC AI Model Bulletin §4 — Risk Mgmt & Internal Controls','US','Validation, testing, retesting and monitoring incl. model drift across the lifecycle.'),
  ('naic-governance','naic_model_bulletin_ai','NAIC AI Model Bulletin §3 — Governance','US','Board-accountable senior management; cross-functional oversight; lines of defense; internal audit.'),
  ('naic-thirdparty','naic_model_bulletin_ai','NAIC AI Model Bulletin §4 — Third-Party AI & Data','US','Due diligence; contractual audit rights; insurer retains compliance responsibility.'),
  ('naic-fairness','naic_model_bulletin_ai','NAIC AI Model Bulletin §2/§3 — Unfair Discrimination','US','Methods to detect and address errors, bias and unfair discrimination.'),
  ('naic-data','naic_model_bulletin_ai','NAIC AI Model Bulletin §3 — Data Practices','US','Currency, lineage, quality, integrity, bias minimization and suitability of data.'),
  ('naic-notice','naic_model_bulletin_ai','NAIC AI Model Bulletin §1.9 — Consumer Notice','US','Notice to impacted consumers that AI Systems are in use.'),
  ('eu-art9','eu_ai_act','EU AI Act Art 9 — Risk Management System','EU','Continuous iterative risk-management across the high-risk AI lifecycle.'),
  ('eu-art10','eu_ai_act','EU AI Act Art 10 — Data and Data Governance','EU','Training/validation/test data quality, representativeness, bias examination, origin.'),
  ('eu-art12','eu_ai_act','EU AI Act Art 12/19 — Record-Keeping & Logs','EU','Automatic recording of events (logs) over the system lifetime for traceability.'),
  ('eu-art14','eu_ai_act','EU AI Act Art 14 — Human Oversight','EU','Oversight measures incl. interpret output, decide not to use, override, stop.'),
  ('eu-art15','eu_ai_act','EU AI Act Art 15 — Accuracy, Robustness, Cybersecurity','EU','Declared accuracy, robustness/resilience, and cybersecurity of the AI system.'),
  ('eu-art17','eu_ai_act','EU AI Act Art 17 — Quality Management System','EU','Documented QMS covering the AI system lifecycle.'),
  ('eu-art26','eu_ai_act','EU AI Act Art 26 — Deployer Obligations','EU','Use per instructions, assign competent oversight, ensure input representativeness, monitor, retain logs ≥6mo.'),
  ('eu-art27','eu_ai_act','EU AI Act Art 27 — Fundamental Rights Impact Assessment','EU','FRIA before deployment for Annex III 5(c) (insurance) deployers; notify authority.'),
  ('eu-art50','eu_ai_act','EU AI Act Art 50 — Transparency to Persons','EU','Inform natural persons they are interacting with / subject to an AI system.'),
  ('eu-art72','eu_ai_act','EU AI Act Art 72 — Post-Market Monitoring','EU','Provider post-market monitoring plan over the system lifetime.'),
  ('eu-art73','eu_ai_act','EU AI Act Art 73 — Serious Incident Reporting','EU','Report serious incidents to authorities within set deadlines.'),
  ('dfs-validity','nydfs','NY DFS CL-7 §II.A ¶12 — Data Validity & Proxy','NY','Actuarial validity + proxy/correlation assessment of ECDIS vs protected classes.'),
  ('dfs-testing','nydfs','NY DFS CL-7 §II.C ¶17-18 — Quantitative Testing','NY','AIR, SMD, Z/T-tests; pre-prod, on change, and on a regular cadence.'),
  ('dfs-governance','nydfs','NY DFS CL-7 §III.B ¶26 — Board Governance','NY','Board approves AIS policies at least annually; senior-management ownership.'),
  ('dfs-thirdparty','nydfs','NY DFS CL-7 §III — Third-Party Vendors','NY','Vendor management; insurer retains responsibility; no proprietary shield.'),
  ('dfs-disclosure','nydfs','NY DFS CL-7 §IV.E ¶39 — Consumer Disclosure','NY','Disclose AIS use and external-vendor data use to consumers.'),
  ('dfs-adverse','nydfs','NY DFS CL-7 §IV.E ¶39-44 — Adverse Action','NY','Specific reasons + data elements + source; no vendor-proprietary shield; ≤15 days.'),
  ('co-1104','colorado_sb21_169','C.R.S. §10-3-1104.9 + 3 CCR 702-10 — ECDIS','CO','Prohibit unfair discrimination from ECDIS/models; governance + testing (testing reg distinct).'),
  ('gdpr-art5','gdpr','GDPR Art 5(1)(b)(c) — Purpose Limitation & Minimization','EU','Adequate, relevant, limited to what is necessary; purpose limitation.'),
  ('gdpr-art9','gdpr','GDPR Art 9 — Special Categories','EU','Special-category data processing prohibited absent a lawful basis + safeguards.'),
  ('gdpr-art22','gdpr','GDPR Art 22(3) — Automated Decisions','EU','Right to human intervention, to express a view, and to contest the decision.'),
  ('gdpr-art35','gdpr','GDPR Art 35 — Data Protection Impact Assessment','EU','DPIA required for high-risk processing.'),
  ('nist-manage','nist_ai_rmf','NIST AI RMF MANAGE 4.x — Incident Response','US','Mechanisms to track, respond to, and recover from AI incidents.')
) AS v(code,fw,cite,juris,txt)
WHERE NOT EXISTS (SELECT 1 FROM core.regulatory_provision p WHERE p.provision_code = v.code AND p.valid_to = '2099-12-31 00:00:00+00');

-- Canonical requirements (one governance domain each)
INSERT INTO core.canonical_requirement (requirement_code, governance_domain_code, title, text)
SELECT v.code, v.dom, v.title, v.txt FROM (VALUES
  ('mr-model-risk-rating','model_risk','Per-model risk rating','A per-model risk rating (materiality × complexity × breadth) selects the applicable control tier.'),
  ('mr-model-validation','model_risk','Independent model validation','Independent second-line validation of conceptual soundness, monitoring and outcomes before production.'),
  ('mr-effective-challenge','model_risk','Independent effective challenge','Objective challenge with authority to restrict or halt model use.'),
  ('mr-performance-monitoring','model_risk','Performance & drift monitoring','Defined metrics with numeric thresholds; ongoing monitoring and drift testing.'),
  ('mr-change-control','model_risk','Change management & re-validation','Version control; material change triggers re-validation before redeploy.'),
  ('fair-disparate-impact','fairness','Disparate-impact testing','Quantitative testing of consumer outcomes for unfair discrimination across protected classes.'),
  ('fair-proxy-analysis','fairness','Proxy / correlated-attribute analysis','Correlation/proxy testing of external data vs protected-class status.'),
  ('fair-fria','fairness','Fundamental rights impact assessment','FRIA before deployment for in-scope insurance AI; authority notified.'),
  ('pr-dpia','privacy','Data protection impact assessment','GDPR DPIA completed and referenced before deployment.'),
  ('pr-special-category','privacy','Special-category data handling','Lawful basis + safeguards + minimization for special-category personal data.'),
  ('pr-data-minimization','privacy','Data minimization & purpose limitation','Only necessary features for a documented purpose are processed.'),
  ('dg-data-quality','data_governance','Data quality & representativeness','Documented, representative, error-checked training/validation/test data.'),
  ('dg-data-provenance','data_governance','Data provenance & actuarial validity','Inventoried provenance + demonstrated empirical/actuarial validity of data→outcome.'),
  ('dg-record-keeping','data_governance','Automatic logging & retention','Automatic event logging over the lifetime; deployer log retention ≥6 months.'),
  ('ho-human-review','human_oversight','Effective human oversight','Competent reviewer with override authority for adverse automated decisions.'),
  ('ho-stop-mechanism','human_oversight','Safe-halt control','A tested mechanism to halt or interrupt the system.'),
  ('ho-right-to-contest','human_oversight','Right to human intervention & contest','Channel for human intervention and to contest an automated decision within an SLA.'),
  ('tr-ai-disclosure','transparency','Disclosure that AI/ECDIS is used','Consumer disclosure that AI and external data inform the decision.'),
  ('tr-adverse-action','transparency','Adverse-action reasons + data + source','Specific reasons, data elements and their source; no vendor-proprietary shield.'),
  ('sec-cybersecurity','security','Cybersecurity of the AI system','Threat model + controls; resilience to adversarial input; periodic testing.'),
  ('sec-incident-reporting','security','AI incident detection & reporting','Detect, investigate and report serious AI incidents on regulatory deadlines.'),
  ('rob-accuracy-robustness','robustness','Declared accuracy, robustness & resilience','Declared accuracy levels and tested robustness/resilience before deployment.'),
  ('ac-ai-inventory','accountability','Governed AI inventory','Firm-wide inventory with the mandatory field set and an accountable owner.'),
  ('ac-governance-committee','accountability','Board / senior-management governance','Board approves AIS policies ≥annually; cross-functional go/no-go before deploy.'),
  ('ac-internal-audit','accountability','Independent internal audit','Third-line review of AIS-Program/MRM compliance at least annually.'),
  ('ac-qms','accountability','Quality management system','Documented QMS covering the AI lifecycle with assigned responsibilities.'),
  ('ac-third-party-ai','accountability','Third-party / vendor AI due diligence','Vendor diligence + audit rights + contingency; insurer retains responsibility.'),
  ('ac-deployer-obligations','accountability','Deployer obligations','Use per instructions, competent oversight, input representativeness, monitoring & notice.')
) AS v(code,dom,title,txt)
WHERE NOT EXISTS (SELECT 1 FROM core.canonical_requirement c WHERE c.requirement_code = v.code AND c.valid_to = '2099-12-31 00:00:00+00');

-- Requirement tier ladders (cumulative: tier N ⇒ 1..N)
INSERT INTO core.requirement_tier (requirement_id, tier_level, title, criteria)
SELECT cr.requirement_id, v.lvl, v.title, v.criteria FROM (VALUES
  ('mr-model-risk-rating',1,'Risk rating assigned','Per-model risk rating recorded at design-time; selects the tier.'),
  ('mr-model-validation',1,'Model card','Model card to a replicability standard incl. restrictions on use.'),
  ('mr-model-validation',2,'Independent validation','Independent validator approves before deploy (conceptual soundness + monitoring + outcomes).'),
  ('mr-model-validation',3,'Refresh + challenger','Full refresh ≤12mo and on material change; benchmark vs a challenger.'),
  ('mr-effective-challenge',3,'Effective challenge','Independent challenge with authority to restrict use; findings closed before deploy.'),
  ('mr-performance-monitoring',2,'Thresholds defined','Each metric has numeric alert+breach thresholds and an action per breach.'),
  ('mr-performance-monitoring',3,'Continuous monitoring','Automated monitoring (≥daily for execution models) + ≤12mo drift test; 5-day remediation SLA.'),
  ('mr-change-control',2,'Change-triggered revalidation','Version control; material change triggers re-validation before redeploy.'),
  ('fair-disparate-impact',1,'Protected classes documented','Protected classes + proxy rationale documented.'),
  ('fair-disparate-impact',2,'Quantitative test','AIR + SMD per protected class; flag AIR<0.80 or p<0.05; pre-prod + on change + ≥annual.'),
  ('fair-disparate-impact',3,'LDA + monitoring','Less-discriminatory-alternative search + ongoing fairness-metric monitoring.'),
  ('fair-proxy-analysis',2,'Proxy assessment','Correlation/proxy test of each ECDIS feature vs imputed protected-class status.'),
  ('fair-fria',3,'FRIA completed','FRIA before first deployment; authority notified; reference recorded.'),
  ('pr-dpia',2,'DPIA completed','GDPR DPIA completed and referenced before deploy.'),
  ('pr-special-category',2,'Lawful basis + safeguards','Lawful basis + safeguards documented for special-category data.'),
  ('pr-special-category',3,'Minimization + logging','Minimization + access controls enforced; access logged.'),
  ('pr-data-minimization',1,'Necessity verified','Each feature maps to a documented necessary purpose; non-necessary removed.'),
  ('dg-data-quality',1,'Sources documented','Data sources, collection and preparation documented.'),
  ('dg-data-quality',2,'Representativeness assessed','Representativeness + error/gap + data-bias examination with pass/fail per check.'),
  ('dg-data-provenance',1,'Provenance inventoried','Each data source inventoried with provenance.'),
  ('dg-data-provenance',2,'Actuarial validity','Empirical/actuarial validity of each data→outcome relationship demonstrated.'),
  ('dg-record-keeping',1,'Logging + retention','Automatic event logging enabled; logs retained ≥6 months.'),
  ('ho-human-review',1,'Oversight defined','Oversight measures (who reviews, what, override capability) defined.'),
  ('ho-human-review',2,'Reviewer + override path','Named competent reviewer with override authority; override path tested at deploy.'),
  ('ho-human-review',3,'Override events audited','Override/contest events captured and audited at runtime.'),
  ('ho-stop-mechanism',2,'Stop mechanism documented','A halt/interrupt mechanism documented.'),
  ('ho-stop-mechanism',3,'Stop mechanism tested','Stop mechanism tested operational in production.'),
  ('ho-right-to-contest',2,'Contest channel','Contest channel yielding human intervention within an SLA; outcomes logged.'),
  ('tr-ai-disclosure',1,'Disclosure prepared','Consumer disclosure that AI/ECDIS informs the decision prepared.'),
  ('tr-ai-disclosure',2,'Disclosure delivered','Disclosure delivered + captured per decision; 0 missing in audit.'),
  ('tr-adverse-action',2,'Adverse-action notice','≤15-day notice with specific reasons + data + source; no proprietary shield.'),
  ('sec-cybersecurity',1,'Security review','Threat model + controls recorded; deploy blocked without a security review.'),
  ('sec-cybersecurity',3,'Adversarial testing','Periodic adversarial/penetration testing ≤12 months.'),
  ('sec-incident-reporting',1,'Incident process','Process to detect, investigate and report serious incidents on deadline.'),
  ('rob-accuracy-robustness',1,'Accuracy declared','Accuracy metrics + acceptance levels declared in the model card.'),
  ('rob-accuracy-robustness',2,'Robustness tested','Robustness/resilience tested with a pass criterion before deploy.'),
  ('ac-ai-inventory',1,'Inventory record','Registered in the firm-wide inventory with the mandatory field set ≤5 business days.'),
  ('ac-governance-committee',1,'Board policy approval','Board approves AIS policies ≥annually; senior-management ownership.'),
  ('ac-governance-committee',2,'Cross-functional go/no-go','Cross-functional committee records a go/no-go before deploy.'),
  ('ac-internal-audit',3,'Internal audit','Third-line audit of AIS/MRM compliance ≤12 months; reported to the board.'),
  ('ac-qms',1,'QMS maintained','Documented QMS covering the AI lifecycle with assigned responsibilities.'),
  ('ac-third-party-ai',2,'Vendor diligence','Vendor evidence + own-use validation + audit-rights clause + contingency before deploy.'),
  ('ac-deployer-obligations',1,'Deployer duties','Use per instructions, oversight assigned, input representativeness, monitoring + notice.')
) AS v(rcode,lvl,title,criteria)
JOIN core.canonical_requirement cr ON cr.requirement_code = v.rcode AND cr.valid_to = '2099-12-31 00:00:00+00'
WHERE NOT EXISTS (SELECT 1 FROM core.requirement_tier rt WHERE rt.requirement_id = cr.requirement_id AND rt.tier_level = v.lvl AND rt.valid_to = '2099-12-31 00:00:00+00');

-- Controls (one per requirement-tier; SMART; phase/type/enforcement)
INSERT INTO core.control (control_code, title, control_phase_code, control_type_code, enforcement_action_code, description)
SELECT v.code, v.title, v.phase, v.ctype, v.enforce, v.descr FROM (VALUES
  ('ctl-mr-rating','Assign per-model risk rating','design_time','directive','block','Owner assigns materiality×complexity rating; selects control tier.'),
  ('ctl-mr-modelcard','Model card to replicability standard','design_time','directive','block','Owner authors a reproducible model card incl. restrictions on use.'),
  ('ctl-mr-indep-val','Independent validation report','deploy_time','preventive','block','Independent 2nd-line validator approves before deploy.'),
  ('ctl-mr-val-refresh','Validation refresh + challenger','static_model','detective','warn','≤12mo/on-change refresh + challenger benchmark.'),
  ('ctl-mr-challenge','Effective challenge memo','deploy_time','detective','block','Independent challenge with use-restriction authority; findings closed.'),
  ('ctl-mr-thresholds','Numeric monitoring thresholds','deploy_time','preventive','block','Each metric has numeric thresholds + action per breach.'),
  ('ctl-mr-monitoring','Continuous monitoring + drift','execution','detective','warn','Automated monitoring + ≤12mo drift test; 5-day remediation SLA.'),
  ('ctl-mr-change','Change-triggered revalidation','deploy_time','preventive','block','Material change triggers re-validation before redeploy.'),
  ('ctl-fair-doc','Document protected classes','design_time','directive','log_only','Protected classes + proxy rationale documented.'),
  ('ctl-fair-test','Disparate-impact test (AIR/SMD)','static_model','detective','block','AIR+SMD; flag AIR<0.80 or p<0.05; block unresolved breach.'),
  ('ctl-fair-lda','LDA search + fairness monitoring','execution','detective','warn','Less-discriminatory-alternative search + ongoing monitoring.'),
  ('ctl-fair-proxy','Proxy/correlation analysis','static_model','detective','block','Proxy test of each ECDIS feature vs protected-class status.'),
  ('ctl-fair-fria','FRIA completed + notified','design_time','preventive','block','FRIA before first deploy; authority notified.'),
  ('ctl-pr-dpia','DPIA completed','deploy_time','preventive','block','GDPR DPIA completed + referenced before deploy.'),
  ('ctl-pr-sc-basis','Special-category lawful basis','design_time','preventive','block','Lawful basis + safeguards documented.'),
  ('ctl-pr-sc-min','Special-category minimization','execution','detective','warn','Minimization + access controls; access logged.'),
  ('ctl-pr-minimize','Data minimization sign-off','design_time','preventive','block','Each feature mapped to a necessary purpose; non-necessary removed.'),
  ('ctl-dg-doc','Document data sources','design_time','directive','log_only','Sources, collection, preparation documented.'),
  ('ctl-dg-repr','Representativeness assessment','static_model','detective','block','Representativeness + error/gap + bias checks pass/fail.'),
  ('ctl-dg-prov','Provenance inventory','design_time','directive','log_only','Each data source inventoried with provenance.'),
  ('ctl-dg-actuarial','Actuarial-validity demonstration','static_model','detective','block','Empirical/actuarial validity demonstrated.'),
  ('ctl-dg-logs','Logging + ≥6mo retention','deploy_time','preventive','block','Automatic logging enabled; retention ≥6 months.'),
  ('ctl-ho-define','Define oversight measures','design_time','directive','log_only','Oversight measures defined.'),
  ('ctl-ho-reviewer','Reviewer + tested override path','deploy_time','preventive','block','Named reviewer with override authority; override path tested.'),
  ('ctl-ho-audit','Audit override/contest events','execution','detective','warn','Override/contest events captured + audited.'),
  ('ctl-ho-stop-doc','Document stop mechanism','design_time','preventive','block','Halt/interrupt mechanism documented.'),
  ('ctl-ho-stop-test','Test stop mechanism','deploy_time','preventive','block','Stop mechanism tested operational.'),
  ('ctl-ho-contest','Contest channel + SLA','execution','corrective','warn','Human-intervention channel within SLA; outcomes logged.'),
  ('ctl-tr-prep','Prepare AI disclosure','design_time','directive','log_only','Consumer disclosure prepared.'),
  ('ctl-tr-deliver','Deliver AI disclosure','execution','directive','warn','Disclosure delivered + captured per decision.'),
  ('ctl-tr-adverse','Adverse-action notice','execution','corrective','warn','≤15-day notice: reasons + data + source; no proprietary shield.'),
  ('ctl-sec-review','Security review + threat model','design_time','preventive','block','Threat model + controls recorded; deploy blocked without review.'),
  ('ctl-sec-pentest','Adversarial/penetration testing','execution','detective','warn','Periodic adversarial/pen testing ≤12 months.'),
  ('ctl-sec-incident','Incident detect/report process','execution','corrective','warn','Detect/investigate/report serious incidents on deadline.'),
  ('ctl-rob-accuracy','Declare accuracy levels','design_time','directive','block','Accuracy metrics + acceptance levels in the model card.'),
  ('ctl-rob-robust','Test robustness/resilience','static_model','preventive','block','Robustness/resilience tested with a pass criterion.'),
  ('ctl-ac-inventory','Register in AI inventory','design_time','preventive','block','Firm-wide inventory record with mandatory fields ≤5 business days.'),
  ('ctl-ac-board','Board policy approval','design_time','directive','log_only','Board approves AIS policies ≥annually.'),
  ('ctl-ac-committee','Cross-functional go/no-go','deploy_time','preventive','block','Cross-functional committee records a go/no-go before deploy.'),
  ('ctl-ac-audit','Independent internal audit','execution','detective','warn','Third-line audit ≤12mo; reported to the board.'),
  ('ctl-ac-qms','Maintain QMS','design_time','preventive','block','Documented lifecycle QMS with assigned responsibilities.'),
  ('ctl-ac-vendor','Vendor diligence + audit rights','deploy_time','preventive','block','Vendor evidence + own-use validation + audit-rights + contingency.'),
  ('ctl-ac-deployer','Deployer obligations','deploy_time','preventive','block','Use per instructions, oversight, input representativeness, monitoring + notice.')
) AS v(code,title,phase,ctype,enforce,descr)
WHERE NOT EXISTS (SELECT 1 FROM core.control c WHERE c.control_code = v.code AND c.valid_to = '2099-12-31 00:00:00+00');

-- requirement_control: bind each tier to its control
INSERT INTO core.requirement_control (requirement_tier_id, control_id)
SELECT rt.requirement_tier_id, c.control_id FROM (VALUES
  ('mr-model-risk-rating',1,'ctl-mr-rating'),
  ('mr-model-validation',1,'ctl-mr-modelcard'),('mr-model-validation',2,'ctl-mr-indep-val'),('mr-model-validation',3,'ctl-mr-val-refresh'),
  ('mr-effective-challenge',3,'ctl-mr-challenge'),
  ('mr-performance-monitoring',2,'ctl-mr-thresholds'),('mr-performance-monitoring',3,'ctl-mr-monitoring'),
  ('mr-change-control',2,'ctl-mr-change'),
  ('fair-disparate-impact',1,'ctl-fair-doc'),('fair-disparate-impact',2,'ctl-fair-test'),('fair-disparate-impact',3,'ctl-fair-lda'),
  ('fair-proxy-analysis',2,'ctl-fair-proxy'),
  ('fair-fria',3,'ctl-fair-fria'),
  ('pr-dpia',2,'ctl-pr-dpia'),
  ('pr-special-category',2,'ctl-pr-sc-basis'),('pr-special-category',3,'ctl-pr-sc-min'),
  ('pr-data-minimization',1,'ctl-pr-minimize'),
  ('dg-data-quality',1,'ctl-dg-doc'),('dg-data-quality',2,'ctl-dg-repr'),
  ('dg-data-provenance',1,'ctl-dg-prov'),('dg-data-provenance',2,'ctl-dg-actuarial'),
  ('dg-record-keeping',1,'ctl-dg-logs'),
  ('ho-human-review',1,'ctl-ho-define'),('ho-human-review',2,'ctl-ho-reviewer'),('ho-human-review',3,'ctl-ho-audit'),
  ('ho-stop-mechanism',2,'ctl-ho-stop-doc'),('ho-stop-mechanism',3,'ctl-ho-stop-test'),
  ('ho-right-to-contest',2,'ctl-ho-contest'),
  ('tr-ai-disclosure',1,'ctl-tr-prep'),('tr-ai-disclosure',2,'ctl-tr-deliver'),
  ('tr-adverse-action',2,'ctl-tr-adverse'),
  ('sec-cybersecurity',1,'ctl-sec-review'),('sec-cybersecurity',3,'ctl-sec-pentest'),
  ('sec-incident-reporting',1,'ctl-sec-incident'),
  ('rob-accuracy-robustness',1,'ctl-rob-accuracy'),('rob-accuracy-robustness',2,'ctl-rob-robust'),
  ('ac-ai-inventory',1,'ctl-ac-inventory'),
  ('ac-governance-committee',1,'ctl-ac-board'),('ac-governance-committee',2,'ctl-ac-committee'),
  ('ac-internal-audit',3,'ctl-ac-audit'),
  ('ac-qms',1,'ctl-ac-qms'),
  ('ac-third-party-ai',2,'ctl-ac-vendor'),
  ('ac-deployer-obligations',1,'ctl-ac-deployer')
) AS v(rcode,lvl,ccode)
JOIN core.canonical_requirement cr ON cr.requirement_code = v.rcode AND cr.valid_to = '2099-12-31 00:00:00+00'
JOIN core.requirement_tier rt ON rt.requirement_id = cr.requirement_id AND rt.tier_level = v.lvl AND rt.valid_to = '2099-12-31 00:00:00+00'
JOIN core.control c ON c.control_code = v.ccode AND c.valid_to = '2099-12-31 00:00:00+00'
WHERE NOT EXISTS (SELECT 1 FROM core.requirement_control rc WHERE rc.requirement_tier_id = rt.requirement_tier_id AND rc.control_id = c.control_id AND rc.valid_to = '2099-12-31 00:00:00+00');

-- evidence_specification: the artifact that proves each control
INSERT INTO core.evidence_specification (control_id, evidence_artifact_type_code, produced_by, citable_as)
SELECT c.control_id, v.atype, v.producedby, v.citable FROM (VALUES
  ('ctl-mr-rating','config_snapshot','model owner','Model risk rating'),
  ('ctl-mr-modelcard','model_card','model owner','Model card'),
  ('ctl-mr-indep-val','validation_report','independent validator','Validation report'),
  ('ctl-mr-val-refresh','validation_report','independent validator','Validation refresh + challenger'),
  ('ctl-mr-challenge','validation_report','second line','Effective-challenge memo'),
  ('ctl-mr-thresholds','config_snapshot','model owner','Monitoring thresholds'),
  ('ctl-mr-monitoring','test_result','first-line MRM','Monitoring + drift results'),
  ('ctl-mr-change','config_snapshot','MLOps','Change/version record'),
  ('ctl-fair-doc','document','model owner','Protected-class documentation'),
  ('ctl-fair-test','test_result','data science','Disparate-impact test result'),
  ('ctl-fair-lda','validation_report','data science','LDA + monitoring report'),
  ('ctl-fair-proxy','test_result','actuarial','Proxy analysis result'),
  ('ctl-fair-fria','document','compliance','FRIA'),
  ('ctl-pr-dpia','document','DPO','DPIA'),
  ('ctl-pr-sc-basis','document','DPO','Special-category basis + safeguards'),
  ('ctl-pr-sc-min','decision_log','platform','Special-category access log'),
  ('ctl-pr-minimize','document','DPO','Data-minimization register'),
  ('ctl-dg-doc','document','data owner','Data-source documentation'),
  ('ctl-dg-repr','validation_report','data owner','Representativeness assessment'),
  ('ctl-dg-prov','document','data owner','Provenance inventory'),
  ('ctl-dg-actuarial','validation_report','actuarial','Actuarial-validity report'),
  ('ctl-dg-logs','config_snapshot','MLOps','Log-retention configuration'),
  ('ctl-ho-define','document','model owner','Oversight design'),
  ('ctl-ho-reviewer','approval_record','underwriting ops','Reviewer + override-path test'),
  ('ctl-ho-audit','decision_log','platform','Override/contest audit log'),
  ('ctl-ho-stop-doc','document','model owner','Stop-mechanism design'),
  ('ctl-ho-stop-test','test_result','MLOps','Stop-mechanism test'),
  ('ctl-ho-contest','decision_log','customer ops','Contest/intervention log'),
  ('ctl-tr-prep','document','customer ops','AI disclosure copy'),
  ('ctl-tr-deliver','decision_log','customer ops','Disclosure delivery log'),
  ('ctl-tr-adverse','decision_log','customer ops','Adverse-action notice log'),
  ('ctl-sec-review','document','security','Security review + threat model'),
  ('ctl-sec-pentest','test_result','security','Adversarial/pen-test report'),
  ('ctl-sec-incident','decision_log','incident manager','Incident log'),
  ('ctl-rob-accuracy','model_card','model owner','Accuracy declaration'),
  ('ctl-rob-robust','validation_report','validation','Robustness test report'),
  ('ctl-ac-inventory','config_snapshot','accountable owner','AI inventory record'),
  ('ctl-ac-board','approval_record','board/committee','Board policy approval'),
  ('ctl-ac-committee','approval_record','governance committee','Go/no-go record'),
  ('ctl-ac-audit','validation_report','internal audit','Internal audit report'),
  ('ctl-ac-qms','document','compliance','QMS documentation'),
  ('ctl-ac-vendor','approval_record','procurement + compliance','Vendor diligence package'),
  ('ctl-ac-deployer','approval_record','deployer','Deployer-obligations attestation')
) AS v(ccode,atype,producedby,citable)
JOIN core.control c ON c.control_code = v.ccode AND c.valid_to = '2099-12-31 00:00:00+00'
WHERE NOT EXISTS (SELECT 1 FROM core.evidence_specification es WHERE es.control_id = c.control_id AND es.evidence_artifact_type_code = v.atype AND es.valid_to = '2099-12-31 00:00:00+00');

-- provision_requirement: map provisions → canonical requirements (by minimum tier)
INSERT INTO core.provision_requirement (provision_id, requirement_id, min_tier_level)
SELECT p.provision_id, cr.requirement_id, v.mintier FROM (VALUES
  ('sr262-rating','mr-model-risk-rating',1),('naic-governance','mr-model-risk-rating',1),
  ('sr262-validation','mr-model-validation',1),('naic-validation','mr-model-validation',2),('eu-art9','mr-model-validation',2),
  ('sr262-challenge','mr-effective-challenge',3),
  ('eu-art72','mr-performance-monitoring',2),('naic-validation','mr-performance-monitoring',2),('dfs-governance','mr-performance-monitoring',2),
  ('sr262-change','mr-change-control',2),
  ('dfs-testing','fair-disparate-impact',2),('co-1104','fair-disparate-impact',2),('eu-art10','fair-disparate-impact',2),('naic-fairness','fair-disparate-impact',2),
  ('dfs-validity','fair-proxy-analysis',2),('co-1104','fair-proxy-analysis',2),
  ('eu-art27','fair-fria',3),
  ('gdpr-art35','pr-dpia',2),
  ('gdpr-art9','pr-special-category',2),('eu-art10','pr-special-category',2),
  ('gdpr-art5','pr-data-minimization',1),
  ('eu-art10','dg-data-quality',1),('naic-data','dg-data-quality',2),
  ('dfs-validity','dg-data-provenance',2),('eu-art10','dg-data-provenance',1),('co-1104','dg-data-provenance',1),
  ('eu-art12','dg-record-keeping',1),('eu-art26','dg-record-keeping',1),
  ('eu-art14','ho-human-review',1),('eu-art26','ho-human-review',2),
  ('eu-art14','ho-stop-mechanism',2),
  ('gdpr-art22','ho-right-to-contest',2),
  ('dfs-disclosure','tr-ai-disclosure',1),('eu-art50','tr-ai-disclosure',1),
  ('dfs-adverse','tr-adverse-action',2),
  ('eu-art15','sec-cybersecurity',1),
  ('eu-art73','sec-incident-reporting',1),('nist-manage','sec-incident-reporting',1),
  ('eu-art15','rob-accuracy-robustness',1),('naic-validation','rob-accuracy-robustness',2),
  ('sr262-inventory','ac-ai-inventory',1),('naic-governance','ac-ai-inventory',1),('co-1104','ac-ai-inventory',1),
  ('dfs-governance','ac-governance-committee',1),('naic-governance','ac-governance-committee',2),
  ('naic-governance','ac-internal-audit',3),
  ('eu-art17','ac-qms',1),
  ('sr262-vendor','ac-third-party-ai',2),('naic-thirdparty','ac-third-party-ai',2),('dfs-thirdparty','ac-third-party-ai',2),
  ('eu-art26','ac-deployer-obligations',1)
) AS v(pcode,rcode,mintier)
JOIN core.regulatory_provision p ON p.provision_code = v.pcode AND p.valid_to = '2099-12-31 00:00:00+00'
JOIN core.canonical_requirement cr ON cr.requirement_code = v.rcode AND cr.valid_to = '2099-12-31 00:00:00+00'
WHERE NOT EXISTS (SELECT 1 FROM core.provision_requirement pr WHERE pr.provision_id = p.provision_id AND pr.requirement_id = cr.requirement_id AND pr.valid_to = '2099-12-31 00:00:00+00');
