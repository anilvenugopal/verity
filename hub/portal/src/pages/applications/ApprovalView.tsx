import { useEffect, useRef, useState } from 'react'
import { useNavigate, useParams } from 'react-router-dom'
import { api, ApiException } from '@/api/client'
import { useSession } from '@/auth/useSession'
import type { Application, ApprovalRequest } from '@/api/types'
import { Badge } from '@/components/Badge'
import './ApprovalView.css'

interface Code { code: string; label: string }
interface Ref {
  data_classifications: Code[]
  lines_of_business: Code[]
  frameworks: Code[]
  governance_domains: Code[]
  jurisdictions: Code[]
}

const ROLE_LABEL: Record<string, string> = {
  ai_governance: 'AI Governance', business_owner: 'Business Owner', security: 'Security',
  compliance: 'Compliance', legal: 'Legal', model_risk: 'Model Risk', privacy: 'Privacy',
}
const roleLabel = (c: string) => ROLE_LABEL[c] ?? c.replace(/_/g, ' ').replace(/\b\w/g, (m) => m.toUpperCase())
const DECISION_LABEL: Record<string, string> = {
  approved: 'Approved', rejected: 'Rejected', requested_changes: 'Requested changes', abstained: 'Abstained',
}
const KIND_TITLE: Record<string, string> = { application_onboarding: 'Review onboarding' }
const labelOf = (codes: Code[] | undefined, code: string | null) =>
  (code && codes?.find((c) => c.code === code)?.label) || code || '—'

// Shared approval primitive (US2), kind-aware. application_onboarding renders the target app's
// identity + compliance perimeter; the sign-off gate matches required_roles to recorded sign-offs.
// Decisions are scroll-gated (must review before signing) and POST /approvals/{id}/signoff. M4 reuses
// this view for intake tier-quorum (kind=intake) once intake detail is available.
export function ApprovalView() {
  const { id } = useParams<{ id: string }>()
  const navigate = useNavigate()
  const { principal } = useSession()
  const [appr, setAppr] = useState<ApprovalRequest | null>(null)
  const [app, setApp] = useState<Application | null>(null)
  const [ref, setRef] = useState<Ref | null>(null)
  const [notFound, setNotFound] = useState(false)
  const [comment, setComment] = useState('')
  const [busy, setBusy] = useState(false)
  const [error, setError] = useState('')
  const [reviewed, setReviewed] = useState(false)
  const sentinel = useRef<HTMLDivElement>(null)

  useEffect(() => {
    if (!id) return
    api.get<ApprovalRequest>(`/api/approvals/${id}`).then(setAppr).catch((e) => {
      if (e instanceof ApiException && e.status === 404) setNotFound(true)
    })
    api.get<Ref>('/api/reference/onboarding').then(setRef).catch(() => undefined)
  }, [id])

  // load the target once the approval (and its target id) is known
  useEffect(() => {
    if (appr?.target_application_id) api.get<Application>(`/api/applications/${appr.target_application_id}`).then(setApp).catch(() => undefined)
  }, [appr?.target_application_id])

  // scroll-gate: enable decisions only once the end of the request has been seen (short pages pass immediately)
  useEffect(() => {
    const el = sentinel.current
    if (!el) return
    const obs = new IntersectionObserver((es) => es.forEach((e) => e.isIntersecting && setReviewed(true)))
    obs.observe(el)
    return () => obs.disconnect()
  }, [app, appr])

  if (notFound) {
    return (
      <div className="canvas-pad"><div className="card"><div className="empty-state">
        <div className="empty-state__title">Approval not found</div>
        <div className="empty-state__actions">
          <button className="btn btn--secondary btn--md" onClick={() => navigate('/applications')}>Back to applications</button>
        </div>
      </div></div></div>
    )
  }
  if (!appr) {
    return <div className="canvas-pad"><div className="card"><div className="empty-state"><div className="empty-state__body">Loading…</div></div></div></div>
  }

  const yn = (v: boolean) => <span className={`yn yn--${v ? 'y' : 'n'}`}>{v ? 'Yes' : 'No'}</span>
  const pending = appr.status_code === 'pending'
  const myRoles = principal?.platform_roles ?? []
  const iSigned = !!principal && appr.signoffs.some((s) => s.approver_actor_id === principal.actor_id)
  const myRequiredRole = appr.required_roles.find((r) => myRoles.includes(r))
  const canSign = pending && !iSigned && !!myRequiredRole

  async function decide(decision_code: string) {
    if (!id || busy) return
    setBusy(true)
    setError('')
    try {
      const updated = await api.post<ApprovalRequest>(`/api/approvals/${id}/signoff`, { decision_code, comment: comment || null })
      setAppr(updated)
      setComment('')
    } catch (e) {
      setError(e instanceof ApiException ? e.body.detail : 'Sign-off failed.')
    } finally {
      setBusy(false)
    }
  }

  return (
    <div className="canvas-pad">
      <div className="page-head">
        <div>
          <div className="page-head__title l-cluster">
            {app ? app.name : KIND_TITLE[appr.request_kind_code] ?? 'Approval'}
            {app && <span className="tla">{app.code}</span>}
            <Badge table="approval_request_status" code={appr.status_code} quiet />
          </div>
          <div className="page-head__sub">
            {KIND_TITLE[appr.request_kind_code] ?? appr.request_kind_code} · requires {appr.required_roles.map(roleLabel).join(' + ')}
          </div>
        </div>
      </div>

      <div className="callout callout--warning">
        <svg className="icon callout__icon" aria-hidden="true"><use href="#i-callout-warning" /></svg>
        <div className="callout__body">
          <span className="callout__title">All sign-offs required.</span>
          This request needs {appr.required_roles.map(roleLabel).join(' and ')}. The application stays <strong>pending</strong> — and cannot own promotable assets — until every required role approves.
        </div>
      </div>

      {app && (
        <>
          <div className="section">
            <div className="section__head"><span className="eyebrow">Identity</span></div>
            <div className="card">
              <div className="kv">
                <span className="kv__k">Name</span><span className="kv__v">{app.name}</span>
                <span className="kv__k">Acronym (TLA)</span><span className="kv__v"><span className="tla">{app.code}</span></span>
                <span className="kv__k">Purpose</span><span className="kv__v">{app.description}</span>
                <span className="kv__k">Line of business</span><span className="kv__v">{labelOf(ref?.lines_of_business, app.line_of_business_code)}</span>
              </div>
            </div>
          </div>

          <div className="section">
            <div className="section__head"><span className="eyebrow">Compliance context</span></div>
            <div className="card">
              <div className="kv">
                <span className="kv__k">Data classification</span><span className="kv__v">{labelOf(ref?.data_classifications, app.data_classification_code)} <span className="u-text-tertiary">(ceiling)</span></span>
                <span className="kv__k">Frameworks</span><span className="kv__v">{app.regulatory_framework_codes.map((c) => <span key={c} className="chip chip--static">{labelOf(ref?.frameworks, c)}</span>)}</span>
                <span className="kv__k">Governance domains</span><span className="kv__v">{app.governance_domain_codes.map((c) => <span key={c} className="chip chip--static">{labelOf(ref?.governance_domains, c)}</span>)}</span>
                <span className="kv__k">Decisions affecting consumers</span><span className="kv__v">{yn(app.affects_consumers)}</span>
                <span className="kv__k">Processes PII / PHI</span><span className="kv__v">{yn(app.processes_pii)}</span>
                <span className="kv__k">Consumer-facing</span><span className="kv__v">{yn(app.consumer_facing)}</span>
                <span className="kv__k">Jurisdictions</span><span className="kv__v">{app.jurisdiction_codes.map((c) => <span key={c} className="chip chip--static">{labelOf(ref?.jurisdictions, c)}</span>)}</span>
              </div>
            </div>
          </div>
        </>
      )}

      <div className="section">
        <div className="section__head"><span className="eyebrow">Sign-off</span></div>
        <div className="card">
          <div className="appr">
            {appr.required_roles.map((role) => {
              const s = appr.signoffs.find((x) => x.signed_as_role_code === role)
              const mine = s && principal && s.approver_actor_id === principal.actor_id
              const stateMod = !s ? 'wait' : s.decision_code === 'approved' ? 'done' : s.decision_code === 'rejected' ? 'rejected' : 'wait'
              return (
                <div className="appr__row" key={role}>
                  <span className="appr__role">{roleLabel(role)}</span>
                  <span className="appr__who">{s ? (mine ? 'You' : '—') : myRequiredRole === role ? 'You' : '—'}</span>
                  <span className={`appr__state appr__state--${stateMod}`}>
                    <svg className="icon icon--sm" aria-hidden="true"><use href={`#${s ? (s.decision_code === 'approved' ? 'i-metric-pass' : 'i-block-code') : 'i-triage-challenger-lag'}`} /></svg>
                    {s ? DECISION_LABEL[s.decision_code] ?? s.decision_code : 'Awaiting decision'}
                  </span>
                </div>
              )
            })}
          </div>
        </div>
      </div>

      <div ref={sentinel} aria-hidden="true" />

      {canSign ? (
        <>
          <div className="section">
            <div className="form-field">
              <label className="form-label" htmlFor="appr-comment">Comment <span className="input-hint">(required for reject / request changes)</span></label>
              <textarea className="input" id="appr-comment" placeholder="Recorded with your decision." value={comment} onChange={(e) => setComment(e.target.value)} />
            </div>
          </div>
          {error && (
            <div className="callout callout--error">
              <svg className="icon callout__icon" aria-hidden="true"><use href="#i-callout-info" /></svg>
              <div className="callout__body">{error}</div>
            </div>
          )}
          <div className="form-actions">
            <div className="form-actions__summary">
              Signing as <b>{roleLabel(myRequiredRole!)}</b>
              {!reviewed && ' · scroll through the request to enable your decision'}
            </div>
            <span className="l-spacer" />
            <button className="btn btn--danger btn--md" disabled={!reviewed || busy || !comment.trim()} onClick={() => decide('rejected')}>Reject…</button>
            <button className="btn btn--secondary btn--md" disabled={!reviewed || busy || !comment.trim()} onClick={() => decide('requested_changes')}>Request changes…</button>
            <button className="btn btn--positive btn--md" disabled={!reviewed || busy} onClick={() => decide('approved')}>
              <svg className="icon icon--sm" aria-hidden="true"><use href="#i-approve" /></svg>{busy ? 'Submitting…' : 'Approve'}
            </button>
          </div>
        </>
      ) : (
        <div className="callout callout--info">
          <svg className="icon callout__icon" aria-hidden="true"><use href="#i-callout-info" /></svg>
          <div className="callout__body">
            {!pending ? `This request is ${appr.status_code}.` : iSigned ? 'You have already recorded your decision.' : 'You do not hold a required role for this approval.'}
          </div>
        </div>
      )}
    </div>
  )
}
