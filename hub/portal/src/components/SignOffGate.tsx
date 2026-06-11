import { useState } from 'react'
import { api, ApiException } from '@/api/client'
import { useSession } from '@/auth/useSession'
import { useToast } from '@/shell/useToast'
import type { ApprovalRequest } from '@/api/types'

const ROLE_LABEL: Record<string, string> = {
  ai_governance: 'AI Governance', business_owner: 'Business Owner', security: 'Security',
  compliance: 'Compliance', legal: 'Legal', model_risk: 'Model Risk', privacy: 'Privacy',
}
const roleLabel = (c: string) => ROLE_LABEL[c] ?? c.replace(/_/g, ' ').replace(/\b\w/g, (m) => m.toUpperCase())
const DECISION_LABEL: Record<string, string> = {
  approved: 'Approved', rejected: 'Rejected', requested_changes: 'Requested changes', abstained: 'Abstained',
}

// The shared, tab-gated quorum sign-off gate (FR-019/FR-029). Extracted from the application
// workspace's Governance & Approval rail and reused verbatim on the intake detail with kind=intake.
// Renders the required-role rows + the decision actions — Approve / Request changes / Reject (both
// negatives close the request). The submitter's own action is disabled (separation of duty, FR-030);
// the backend is the real authority. Does the sign-off POST and hands the updated approval to
// onChange so the host can re-pull its entity (status may roll up to active/approved/rejected).
export function SignOffGate({ approval, reviewed, reviewHint, onChange }: {
  approval: ApprovalRequest
  reviewed?: boolean
  reviewHint?: string
  onChange: (updated: ApprovalRequest) => void
}) {
  const { principal } = useSession()
  const { success } = useToast()
  const [comment, setComment] = useState('')
  const [busy, setBusy] = useState(false)
  const [error, setError] = useState('')

  const pending = approval.status_code === 'pending'
  const myRoles = principal?.platform_roles ?? []
  const iSigned = !!principal && approval.signoffs.some((s) => s.approver_actor_id === principal.actor_id)
  const myRequiredRole = approval.required_roles.find((r) => myRoles.includes(r))
  const isSubmitter = !!principal && String(approval.opened_by_actor_id) === String(principal.actor_id)
  const gateOk = reviewed !== false // undefined or true → no tab-gate
  const canSign = pending && !iSigned && !!myRequiredRole && !isSubmitter

  const last = approval.signoffs.length ? approval.signoffs[approval.signoffs.length - 1] : undefined
  const outcome = approval.status_code === 'rejected'
    ? { label: last?.decision_code === 'requested_changes' ? 'Changes requested' : 'Rejected', comment: last?.comment }
    : null

  async function decide(decision_code: string) {
    if (busy) return
    setBusy(true); setError('')
    try {
      const updated = await api.post<ApprovalRequest>(`/api/approvals/${approval.approval_request_id}/signoff`, { decision_code, comment: comment || null })
      setComment('')
      success(decision_code === 'approved' ? 'Approved' : 'Decision recorded')
      onChange(updated)
    } catch (e) {
      setError(e instanceof ApiException ? e.body.detail : 'Sign-off failed.')
    } finally {
      setBusy(false)
    }
  }

  return (
    <>
      <div className="appr">
        {approval.required_roles.map((role) => {
          const s = approval.signoffs.find((x) => x.signed_as_role_code === role)
          const mod = !s ? 'wait' : s.decision_code === 'approved' ? 'done' : (s.decision_code === 'rejected' || s.decision_code === 'requested_changes') ? 'rejected' : 'wait'
          return (
            <div className="appr__row" key={role}>
              <span className="appr__role">{roleLabel(role)}</span>
              <span className={`appr__state appr__state--${mod}`}>
                <svg className="icon icon--sm" aria-hidden="true"><use href={`#${s ? (s.decision_code === 'approved' ? 'i-metric-pass' : 'i-block-code') : 'i-triage-challenger-lag'}`} /></svg>
                {s ? DECISION_LABEL[s.decision_code] ?? s.decision_code : 'Awaiting'}
              </span>
            </div>
          )
        })}
      </div>
      {canSign ? (
        <div className="rail-actions">
          <div className="form-field">
            <label className="form-label" htmlFor="appr-comment">Comment <span className="input-hint">(required to reject / request changes)</span></label>
            <textarea className="input" id="appr-comment" placeholder="Recorded with your decision." value={comment} onChange={(e) => setComment(e.target.value)} />
          </div>
          {!gateOk && <span className="input-hint">{reviewHint ?? 'Review everything before deciding.'}</span>}
          {error && <span className="input-error-text">{error}</span>}
          <button className="btn btn--positive btn--md" disabled={!gateOk || busy} onClick={() => decide('approved')}>
            <svg className="icon icon--sm" aria-hidden="true"><use href="#i-approve" /></svg>{busy ? 'Submitting…' : 'Approve'}
          </button>
          <button className="btn btn--secondary btn--md" disabled={!gateOk || busy || !comment.trim()} onClick={() => decide('requested_changes')}>Request changes</button>
          <button className="btn btn--danger btn--md" disabled={!gateOk || busy || !comment.trim()} onClick={() => decide('rejected')}>Reject</button>
        </div>
      ) : (
        <div className="rail-actions">
          {outcome ? (
            <p className="input-error-text"><b>{outcome.label}.</b>{outcome.comment ? ` ${outcome.comment}` : ''}</p>
          ) : (
            <p className="input-hint">
              {pending
                ? isSubmitter
                  ? 'You submitted this — a different approver must sign off (separation of duty).'
                  : iSigned
                    ? 'You have recorded your decision.'
                    : 'Awaiting the required sign-off(s).'
                : `This request is ${approval.status_code}.`}
            </p>
          )}
        </div>
      )}
    </>
  )
}
