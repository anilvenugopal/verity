// Per-field guidance for the assessment (the "explain everything" requirement, FR-026), grounded in
// the framework language: EU AI Act (Art 9/10/14/27, Annex III), NIST AI RMF, NAIC Model Bulletin,
// NY DFS CL-7, Colorado SB21-169, GDPR Art 22. Each field carries inline helper text; consequential
// fields also carry a "why it matters" line and per-option consequences shown in the Learn-more modal.

export interface Opt {
  value: string
  label: string
  note?: string // the consequence of choosing this option (shown in the Learn-more modal)
}
export interface FieldDef {
  label: string
  help: string // inline helper text (always visible)
  why?: string // "why this matters" (Learn-more modal)
  options?: Opt[]
}

export const FIELDS: Record<string, FieldDef> = {
  // ── Decision context ──
  decision_type: {
    label: 'Decision type',
    help: 'The insurance decision this AI supports.',
    why: 'Underwriting, pricing, claims, fraud and eligibility are consumer-consequential insurance decisions (NAIC risk dimension 1) — they raise the inherent risk tier.',
    options: [
      { value: 'underwriting', label: 'Underwriting', note: 'Consequential insurance decision → raises tier when it affects consumers.' },
      { value: 'pricing', label: 'Pricing / rating', note: 'Consequential → fairness & rate-adequacy scrutiny.' },
      { value: 'claims', label: 'Claims', note: 'Consequential → claim outcomes affect consumers directly.' },
      { value: 'fraud', label: 'Fraud detection', note: 'Consequential → adverse-action and bias scrutiny.' },
      { value: 'eligibility', label: 'Eligibility', note: 'Consequential → may deny coverage/benefits.' },
      { value: 'marketing', label: 'Marketing', note: 'Lower consequence unless it gates access.' },
      { value: 'servicing', label: 'Servicing', note: 'Lower consequence; depends on effect.' },
      { value: 'internal_ops', label: 'Internal operations', note: 'Internal-only → lowest consequence.' },
    ],
  },
  consumer_effect: {
    label: 'Effect on the consumer',
    help: 'The worst-case effect this decision can have on a policyholder or applicant.',
    why: 'Coverage/eligibility and claim denials are "legal or similarly significant" effects (GDPR Art 22) and drive the tier up (NAIC dimension 2).',
    options: [
      { value: 'none', label: 'None', note: 'No direct consumer effect → lowers tier.' },
      { value: 'marketing_only', label: 'Marketing only', note: 'Minor effect.' },
      { value: 'rate_or_premium', label: 'Rate / premium', note: 'Financial effect → moderate.' },
      { value: 'coverage_or_eligibility', label: 'Coverage / eligibility', note: 'Severe effect → drives High.' },
      { value: 'claim_denial', label: 'Claim denial', note: 'Severe effect → drives High; part of the auto-reject pattern.' },
    ],
  },
  annex_iii_high_risk: {
    label: 'EU AI Act high-risk category',
    help: 'Does this match an Annex III high-risk category (e.g. risk assessment & pricing in life/health insurance)?',
    why: 'An Annex III match makes the system high-risk under the EU AI Act regardless of other answers — it floors the inherent tier at High.',
  },
  solely_automated: {
    label: 'Solely automated decision',
    help: 'Is the decision made without meaningful human involvement?',
    why: 'Solely-automated decisions with legal or similarly-significant effect trigger GDPR Art 22 safeguards (the right to obtain human review).',
  },
  affected_populations: {
    label: 'Affected populations',
    help: 'Everyone affected by the decision — select all that apply.',
    why: 'Consumers and vulnerable groups raise the tier; an internal-only audience lowers it (NAIC dimension 2; EU Art 27 fundamental-rights impact).',
    options: [
      { value: 'internal_only', label: 'Internal only', note: 'No external impact → lowers tier.' },
      { value: 'brokers_agents', label: 'Brokers / agents', note: 'Outside the org → at least Limited.' },
      { value: 'policyholders_consumers', label: 'Policyholders / consumers', note: 'Consumer impact → raises tier.' },
      { value: 'vulnerable', label: 'Vulnerable populations', note: 'Heightened protection → strongest signal.' },
    ],
  },
  deployment_scale: {
    label: 'Deployment scale',
    help: 'How widely the system runs.',
    why: 'Production-wide deployment makes the use case material (NAIC materiality).',
    options: [
      { value: 'pilot', label: 'Pilot', note: 'Smallest footprint.' },
      { value: 'limited', label: 'Limited', note: 'Bounded rollout.' },
      { value: 'production_wide', label: 'Production-wide', note: 'Material by scale.' },
    ],
  },

  // ── Data item ──
  classification: {
    label: 'Data classification',
    help: 'The sensitivity tier of this data asset — drives the intake\'s overall classification ceiling.',
    why: 'The most sensitive asset sets the intake\'s classification floor. Special-category PII requires at least tier3_confidential (FR-IN-018).',
  },
  direction: {
    label: 'Direction',
    help: 'Is this a data input the model consumes, or an output it produces?',
    options: [
      { value: 'input', label: 'Input', note: 'Consumed by the model.' },
      { value: 'output', label: 'Output', note: 'Produced by the model.' },
    ],
  },
  data_type: {
    label: 'Data type',
    help: 'The form of the data.',
    options: [
      { value: 'tabular', label: 'Tabular' }, { value: 'text', label: 'Text' },
      { value: 'image', label: 'Image' }, { value: 'audio', label: 'Audio' },
      { value: 'document', label: 'Document' }, { value: 'derived', label: 'Derived / features' },
    ],
  },
  source: {
    label: 'Source / provenance',
    help: 'Where this data comes from.',
    why: 'Third-party and consumer-provided data carry extra due-diligence, actuarial-validity and disclosure duties (NY DFS CL-7, NAIC; EU Art 10 origin).',
    options: [
      { value: 'internal', label: 'Internal', note: 'First-party systems.' },
      { value: 'third_party', label: 'Third party / vendor', note: 'Adds due-diligence + ECDIS scrutiny.' },
      { value: 'consumer_provided', label: 'Consumer-provided', note: 'Disclosure + consent duties.' },
      { value: 'public', label: 'Public', note: 'Verify licence/appropriateness.' },
      { value: 'synthetic', label: 'Synthetic', note: 'Document generation method.' },
      { value: 'system_generated', label: 'System-generated', note: 'Model/derived output.' },
    ],
  },
  pii_presence: {
    label: 'Personal data',
    help: 'Whether this asset contains personal data, and how identifying it is.',
    why: 'Special-category data (health, biometric, etc.) is the strongest signal and can raise the tier to High; any PII requires at least a Confidential classification (FR-IN-018).',
    options: [
      { value: 'none', label: 'None', note: 'No personal data.' },
      { value: 'indirect', label: 'Indirect / quasi-identifiers', note: 'Re-identification risk.' },
      { value: 'direct', label: 'Direct (name, SSN…)', note: 'Requires ≥ Confidential.' },
      { value: 'special_category', label: 'Special category', note: 'Health/biometric → can drive High.' },
    ],
  },

  // ── Human oversight ──
  autonomy_level: {
    label: 'Autonomy level',
    help: 'How much the system decides on its own.',
    why: 'Higher autonomy with weak oversight raises the tier; an effective stop button or an overridable control lowers it (EU Art 14; NAIC dimension 3).',
    options: [
      { value: 'assists', label: 'Assists a human', note: 'Lowest autonomy — a person decides.' },
      { value: 'recommends_review', label: 'Recommends (human reviews)', note: 'Human reviews before acting.' },
      { value: 'recommends_signoff', label: 'Recommends (human signs off)', note: 'Human approval required to proceed.' },
      { value: 'conditional_auto', label: 'Conditionally automated', note: 'Acts alone within limits → raises tier.' },
      { value: 'fully_auto', label: 'Fully automated', note: 'Acts alone → highest; auto-reject if no oversight + severe consumer harm.' },
    ],
  },
  stop_mechanism: {
    label: 'Stop mechanism',
    help: 'Can a human halt or interrupt the system (a "stop button")?',
    why: 'EU Art 14(4)(e) requires a safe-halt for high-risk systems; its presence is one of the two signals that make oversight effective and lower the inherent tier.',
  },

  // ── Oversight control ──
  stage: {
    label: 'Stage',
    help: 'When the oversight happens.',
    options: [
      { value: 'pre_decision', label: 'Pre-decision review' }, { value: 'real_time', label: 'Real-time monitoring' },
      { value: 'post_hoc', label: 'Post-hoc audit' }, { value: 'exception', label: 'Exception handling' },
      { value: 'troubleshooting', label: 'Troubleshooting' },
    ],
  },
  can_override: {
    label: 'Can override / reverse',
    help: 'Can the responsible person override, reverse or disregard the system’s output?',
    why: 'EU Art 14(4)(d) — an overridable control is what makes oversight "effective"; together with a stop button it lowers the inherent tier.',
  },

  // ── Risk ──
  category: {
    label: 'Category',
    help: 'The kind of risk.',
    options: [
      { value: 'fairness', label: 'Fairness / bias' }, { value: 'privacy', label: 'Privacy' },
      { value: 'safety', label: 'Safety' }, { value: 'transparency', label: 'Transparency' },
      { value: 'robustness', label: 'Robustness' }, { value: 'security', label: 'Security' },
      { value: 'financial', label: 'Financial' },
    ],
  },
  likelihood: {
    label: 'Likelihood',
    help: 'How likely the risk is to occur.',
    options: [
      { value: 'rare', label: 'Rare' }, { value: 'possible', label: 'Possible' },
      { value: 'likely', label: 'Likely' }, { value: 'almost_certain', label: 'Almost certain' },
    ],
  },
  severity: {
    label: 'Severity',
    help: 'How severe the impact would be if it occurred.',
    options: [
      { value: 'minor', label: 'Minor' }, { value: 'moderate', label: 'Moderate' },
      { value: 'major', label: 'Major' }, { value: 'severe', label: 'Severe' },
    ],
  },
  residual: {
    label: 'Residual risk',
    help: 'The risk that remains after mitigation.',
    options: [
      { value: 'low', label: 'Low' }, { value: 'medium', label: 'Medium' }, { value: 'high', label: 'High' },
    ],
  },

  // ── Fairness ──
  disparate_impact_tested: {
    label: 'Disparate-impact tested',
    help: 'Has the model been tested for disparate impact on protected classes?',
    why: 'NY DFS CL-7 and Colorado SB21-169 require quantitative disparate-impact testing for consumer-facing insurance AI.',
  },
}
