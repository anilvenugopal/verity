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

export type AuthState =
  | 'loading'
  | 'authenticated'
  | 'unauthenticated'
  | 'session_expired'
  | 'forbidden'
  | 'disabled'
