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
  required_roles: string[]
  signoffs: SignoffRecord[]
  created_at: string
}

// ── Intake assessment (M4 Phase 8) — mirrors hub/src/verity/hub/assessment/models.py ──
export interface HumanOversight {
  strategy: 'none' | 'on_the_loop' | 'in_the_loop'
  threshold?: string | null
}
export interface AIDecisionImpact {
  decision_role: 'assists' | 'recommends_with_signoff' | 'autonomous'
  decision_domain: 'underwriting' | 'pricing' | 'claims' | 'fraud' | 'marketing' | 'servicing' | 'internal_ops'
  affected_population: 'internal_only' | 'brokers_agents' | 'policyholders_consumers' | 'vulnerable'
  adverse_impact: 'negligible' | 'financial' | 'coverage_or_claim_denial' | 'unfair_discriminatory' | 'safety'
  human_oversight: HumanOversight
  reversibility: 'easily_reversible' | 'reversible_with_effort' | 'irreversible'
  gdpr_art22: boolean
  deployment_scale: 'pilot' | 'limited' | 'production_wide'
}
export interface DataTab {
  description: string
  sources: string[]
  data_classification_code: string
  pii_presence: 'none' | 'direct' | 'indirect' | 'special_category'
  sensitive_categories: string[]
  lawful_basis?: string | null
  residency?: string | null
  retention?: string | null
  use?: string | null
}
// PUT /intakes/{id}/assessment body (security_access is out of M4 scope → null)
export interface AssessmentInput {
  ai_decision_impact: AIDecisionImpact
  data: DataTab
  security_access?: unknown | null
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

export type AuthState =
  | 'loading'
  | 'authenticated'
  | 'unauthenticated'
  | 'session_expired'
  | 'forbidden'
  | 'disabled'
