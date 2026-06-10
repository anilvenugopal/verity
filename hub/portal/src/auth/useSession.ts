import { useContext } from 'react'
import { SessionContext, type SessionValue } from './SessionContext'

// Advisory-only role→action map for showing/hiding affordances. Authorization is ALWAYS the
// API's decision (a 403 is the source of truth); this only governs UI affordances.
// Derived from hub/src/verity/hub/auth/matrix.py (research.md §6).
const ROLE_ACTIONS: Record<string, string[]> = {
  onboard_application: ['ai_governance', 'security'],
  create_intake: ['engineer', 'ai_governance', 'business_owner'],
  edit_intake: ['engineer', 'ai_governance', 'business_owner'], // also gates intake edit-in-place + withdraw
  delete_intake: ['business_owner', 'ai_governance', 'security'], // app-team delete of a revisable intake
  edit_impact_assessment: ['business_owner', 'compliance', 'legal', 'model_risk', 'ai_governance', 'security', 'privacy'], // governance roles capture/edit the assessment
  signoff: ['business_owner', 'compliance', 'legal', 'model_risk', 'ai_governance', 'security', 'privacy'],
}

export function useSession(): SessionValue & {
  isAuthenticated: boolean
  hasRole: (role: string) => boolean
  canDo: (action: string) => boolean
} {
  const ctx = useContext(SessionContext)
  if (!ctx) throw new Error('useSession must be used within <SessionProvider>')

  const roles = ctx.principal?.platform_roles ?? []
  const hasRole = (role: string) => roles.includes(role)
  const canDo = (action: string) => {
    if (action === 'view') return ctx.authState === 'authenticated'
    const allowed = ROLE_ACTIONS[action]
    return allowed ? allowed.some((r) => roles.includes(r)) : false
  }

  return {
    ...ctx,
    isAuthenticated: ctx.authState === 'authenticated',
    hasRole,
    canDo,
  }
}
