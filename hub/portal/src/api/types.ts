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

export type AuthState =
  | 'loading'
  | 'authenticated'
  | 'unauthenticated'
  | 'session_expired'
  | 'forbidden'
  | 'disabled'
