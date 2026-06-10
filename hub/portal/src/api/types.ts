// TypeScript shapes consumed by the portal. Field names mirror the backend Pydantic models
// verbatim (naming gate). See specs/002-ui-shell-auth-onboarding/data-model.md.

export interface AppTeamRole {
  application_id: string
  application_name: string
  role_code: string
}

// GET /me (extended response)
export interface Principal {
  actor_id: string
  display_name: string
  email: string | null
  platform_roles: string[]
  app_team_roles: AppTeamRole[]
  is_mock: boolean
}

export interface ApiError {
  code: string
  detail: string
  request_id: string
}

// Mirrors hub/src/verity/hub/preferences/models.py::UserPreferences
export interface UserPreferences {
  theme_mode: 'light' | 'dark' | 'system'
  theme_palette: 'gray' | 'slate' | 'warm'
}

// Mirrors hub/src/verity/hub/application/models.py::Application
export interface Application {
  application_id: string
  code: string
  name: string
  description: string
  application_status_code: string
  line_of_business_code: string | null
  data_classification_code: string
  business_owner_actor_id: string
  created_by_actor_id: string
  business_owner_name: string | null
  created_by_name: string | null
  regulatory_framework_codes: string[]
  governance_domain_codes: string[]
  jurisdiction_codes: string[]
  affects_consumers: boolean
  processes_pii: boolean
  consumer_facing: boolean
  created_at: string
  // latest-approval review status (read-only; null when never submitted)
  latest_approval_status: string | null
  latest_decision: string | null
}

// Mirrors hub/src/verity/hub/intake/models.py::Intake
export interface Intake {
  intake_id: string
  application_id: string
  title: string
  description: string | null
  intake_status_code: string
  ai_risk_tier_code: string | null
  naic_materiality_code: string | null
  materiality_tier_code: string | null
  created_at: string
}

// Request body for POST /applications/{id}/intakes and PUT /intakes/{id} (mirrors IntakeCreate)
export interface IntakeCreate {
  title: string
  description?: string | null
}

// GET /intakes row — an Intake plus its application name + creator (mirrors IntakeListItem)
export interface IntakeListItem extends Intake {
  application_name: string
  created_by_actor_id: string
}

// Mirrors hub/src/verity/hub/intake/models.py::Requirement
export interface Requirement {
  intake_requirement_id: string
  intake_id: string
  requirement_kind_code: string
  requirement_status_code: string
  title: string
  body: string
  created_at: string
}

// Request body for POST /intakes/{id}/requirements (mirrors RequirementCreate)
export interface RequirementCreate {
  requirement_kind_code: string
  title: string
  body: string
}

// The pre-decision authoring statuses an intake may be edited/withdrawn/deleted in (FR-031). Mirrors
// the backend _LOCKED_STATUSES complement (intake/service.py): everything else is locked.
export const REVISABLE_INTAKE_STATUSES = ['proposed', 'in_review', 'impact_assessment'] as const

export function isIntakeRevisable(statusCode: string): boolean {
  return (REVISABLE_INTAKE_STATUSES as readonly string[]).includes(statusCode)
}

export interface AwaitingApproval {
  approval_request_id: string
  application_id: string
  code: string
  name: string
}

export interface SignoffRecord {
  approver_actor_id: string
  signed_as_role_code: string
  decision_code: string
  comment: string | null
  created_at: string | null
}

export interface ApprovalRequest {
  approval_request_id: string
  request_kind_code: string
  status_code: string
  target_intake_id: string | null
  target_application_id: string | null
  opened_by_actor_id: string // the submitter (separation of duty — disable their own sign-off)
  required_roles: string[]
  signoffs: SignoffRecord[]
  created_at: string
}

// ── Intake assessment (comprehensive sectioned model) — mirrors assessment/models.py + data-model §10 ──
export interface DecisionContext {
  decision_type: string
  consumer_effect: string
  annex_iii_high_risk: boolean
  solely_automated: boolean
  affected_populations: string[]
  deployment_scale: string
}
export interface DataItem {
  name: string
  direction: string
  data_type: string
  source: string
  classification: string
  pii_presence: string
  lawful_basis?: string | null
  retention?: string | null
  notes?: string | null
}
export interface OversightControl {
  name: string
  stage: string
  responsible_role: string
  trigger?: string | null
  can_override: boolean
  what_inspected?: string | null
}
export interface HumanOversight {
  autonomy_level: string
  stop_mechanism: boolean
  controls: OversightControl[]
}
export interface RiskItem {
  description: string
  category: string
  likelihood: string
  severity: string
  mitigation?: string | null
  residual?: string | null
}
export interface FairnessMetric {
  name: string
  group?: string | null
  value?: string | null
}
export interface Fairness {
  disparate_impact_tested: boolean
  protected_classes_tested: string[]
  metrics: FairnessMetric[]
  less_discriminatory_alternative?: string | null
}
// PUT /intakes/{id}/assessment body — one full snapshot
export interface AssessmentInput {
  decision_context: DecisionContext
  data_inventory: DataItem[]
  human_oversight: HumanOversight
  risks?: RiskItem[]
  fairness?: Fairness | null
  data_governance_narrative?: string | null
  rationale?: string | null
}
export interface Computed {
  ai_risk_tier_code: string | null
  naic_materiality_code: string | null
  data_classification_code: string | null
  intake_status_code: string | null
  auto_rejected: boolean
}
export interface AssessmentView {
  intake_id: string
  revision: number
  assessment: Record<string, unknown>
  computed: Computed | null
  created_at: string
}
export interface RevisionMeta {
  revision: number
  valid_from: string
  valid_to: string
  created_by_actor_id: string
}

// ── Compliance Model browser (003 FR-023) — mirrors hub/src/verity/hub/compliance/models.py ──
export interface ComplianceFramework {
  framework_code: string
  name: string
  authority: string | null
  provision_count: number
  requirement_count: number
}
export interface RequirementSummary {
  requirement_code: string
  governance_domain_code: string
  title: string
  frameworks: string[]
  max_tier: number | null
  control_count: number
}
export interface ProvisionView {
  framework_code: string
  citation: string
  jurisdiction: string | null
  min_tier_level: number
}
export interface EvidenceSpec {
  evidence_artifact_type_code: string
  citable_as: string | null
}
export interface ControlView {
  control_code: string
  title: string
  control_phase_code: string
  control_type_code: string
  enforcement_action_code: string
  evidence: EvidenceSpec[]
}
export interface TierView {
  tier_level: number
  title: string
  criteria: string
  controls: ControlView[]
}
export interface RequirementDetail {
  requirement_code: string
  governance_domain_code: string
  title: string
  text: string
  provisions: ProvisionView[]
  tiers: TierView[]
}

export type AuthState =
  | 'loading'
  | 'authenticated'
  | 'unauthenticated'
  | 'session_expired'
  | 'forbidden'
  | 'disabled'
