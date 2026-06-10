import { Fragment, useEffect, useMemo, useState } from 'react'
import { useNavigate, useParams } from 'react-router-dom'
import { api, ApiException } from '@/api/client'
import { useSession } from '@/auth/useSession'
import type { Application, ApprovalRequest, Intake } from '@/api/types'
import { Badge } from '@/components/Badge'
import { ReviewBadge } from '@/components/ReviewBadge'
import './ApplicationWorkspace.css'

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
// data-classification ceiling → at-a-glance sensitivity tone (derived; applications carry no governed tier)
const SENSITIVITY_TONE: Record<string, string> = {
  tier4_pii_restricted: 'negative', tier3_confidential: 'warning', tier2_internal: 'neutral', tier1_public: 'neutral',
}
const labelOf = (codes: Code[] | undefined, code: string | null) =>
  (code && codes?.find((c) => c.code === code)?.label) || code || '—'
const fmt = (iso?: string | null) =>
  iso ? new Date(iso).toLocaleString(undefined, { day: 'numeric', month: 'short', year: 'numeric', hour: '2-digit', minute: '2-digit' }) : ''

const TABS = [
  { key: 'compliance', label: 'Compliance' },
  { key: 'ownership', label: 'Ownership & team' },
  { key: 'usecases', label: 'Use cases' },
]
// the sign-off tab-gate covers only the review tabs (Use cases is navigational, not part of review)
const REVIEW_TABS = ['compliance', 'ownership']

// Application workspace — the shared view/approve shell (Issue 1 + 2). Identity band on top; the
// segments are tabs; Risk Profile + Governance & Approval live in an always-visible right rail so you
// can read and sign in one place. Approve is tab-gated (review every tab first). Create mode (tabbed
// form) folds in next.
export function ApplicationWorkspace() {
  const { id } = useParams<{ id: string }>()
  const navigate = useNavigate()
  const { principal, canDo } = useSession()
  const [app, setApp] = useState<Application | null>(null)
  const [ref, setRef] = useState<Ref | null>(null)
  const [appr, setAppr] = useState<ApprovalRequest | null>(null)
  const [intakes, setIntakes] = useState<Intake[]>([])
  const [notFound, setNotFound] = useState(false)
  const [tab, setTab] = useState('compliance')
  const [visited, setVisited] = useState<Set<string>>(new Set(['compliance']))
  const [comment, setComment] = useState('')
  const [busy, setBusy] = useState(false)
  const [error, setError] = useState('')

  useEffect(() => {
    if (!id) return
    api.get<Application>(`/api/applications/${id}`).then(setApp).catch((e) => {
      if (e instanceof ApiException && e.status === 404) setNotFound(true)
    })
    api.get<Ref>('/api/reference/onboarding').then(setRef).catch(() => undefined)
    api.get<ApprovalRequest>(`/api/applications/${id}/approval`).then(setAppr).catch(() => setAppr(null)) // 404 = no approval
    api.get<Intake[]>(`/api/applications/${id}/intakes`).then(setIntakes).catch(() => undefined)
  }, [id])

  function openTab(k: string) {
    setTab(k)
    setVisited((v) => new Set(v).add(k))
  }

  const history = useMemo(() => {
    if (!app) return []
    const items: { t: string | null; body: string }[] = [{ t: app.created_at, body: 'Application proposed' }]
    if (appr) {
      items.push({ t: appr.created_at, body: 'Submitted for approval' })
      for (const s of appr.signoffs) {
        items.push({ t: s.created_at ?? null, body: `${roleLabel(s.signed_as_role_code)} · ${DECISION_LABEL[s.decision_code] ?? s.decision_code}` })
      }
    }
    return items.sort((a, b) => (a.t ?? '').localeCompare(b.t ?? ''))
  }, [app, appr])

  if (notFound) {
    return (
      <div className="canvas-pad"><div className="card"><div className="empty-state">
        <div className="empty-state__title">Application not found</div>
        <div className="empty-state__actions">
          <button className="btn btn--secondary btn--md" onClick={() => navigate('/applications')}>Back to applications</button>
        </div>
      </div></div></div>
    )
  }
  if (!app) {
    return <div className="canvas-pad"><div className="card"><div className="empty-state"><div className="empty-state__body">Loading…</div></div></div></div>
  }

  const yn = (v: boolean) => <span className={`yn yn--${v ? 'y' : 'n'}`}>{v ? 'Yes' : 'No'}</span>
  const owned = principal && app.business_owner_actor_id === principal.actor_id
  const onboarded = new Date(app.created_at).toLocaleDateString(undefined, { day: 'numeric', month: 'short', year: 'numeric' })

  // sign-off eligibility (tab-gated: must have opened every tab first)
  const pending = appr?.status_code === 'pending'
  const myRoles = principal?.platform_roles ?? []
  const iSigned = !!principal && !!appr?.signoffs.some((s) => s.approver_actor_id === principal.actor_id)
  const myRequiredRole = appr?.required_roles.find((r) => myRoles.includes(r))
  const allReviewed = REVIEW_TABS.every((k) => visited.has(k))
  const canSign = pending && !iSigned && !!myRequiredRole

  // remediation: a closed (rejected/changes-requested) approval, and whether this user may edit.
  // The backend allows the proposer OR owner; the workspace only knows the owner, so non-owner
  // proposers reach edit via the URL. canEdit also covers a never-submitted draft (no approval).
  const last = appr?.signoffs.length ? appr.signoffs[appr.signoffs.length - 1] : undefined
  const outcome = appr?.status_code === 'rejected'
    ? { label: last?.decision_code === 'requested_changes' ? 'Changes requested' : 'Rejected', comment: last?.comment }
    : null
  // edit is available for any still-pending application (draft / in review / rejected) to anyone who
  // can onboard — the app team remediates, identity isn't required to match the (mock) owner.
  // Re-submitting supersedes a prior pending approval server-side.
  const canEdit = app.application_status_code === 'pending' && canDo('onboard_application')
  const editBtn = canEdit && (
    <button className="btn btn--primary btn--md" onClick={() => navigate(`/applications/${app.application_id}/edit`)}>Edit &amp; re-submit</button>
  )
  // the requester may cancel a live (pending) request, returning the app to an editable draft
  const cancelBtn = pending && canDo('onboard_application') && (
    <button className="btn btn--ghost btn--md" disabled={busy} onClick={withdraw}>Cancel request</button>
  )
  // the app team may delete a still-pending application (draft / in review / rejected)
  const deleteBtn = canEdit && (
    <button className="btn btn--danger btn--md" disabled={busy} onClick={del}>Delete</button>
  )

  async function withdraw() {
    if (!app || busy) return
    setBusy(true); setError('')
    try {
      const fresh = await api.post<Application>(`/api/applications/${app.application_id}/withdraw`, {})
      setApp(fresh)
      setAppr(await api.get<ApprovalRequest>(`/api/applications/${app.application_id}/approval`).catch(() => null))
    } catch (e) {
      setError(e instanceof ApiException ? e.body.detail : 'Cancel failed.')
    } finally {
      setBusy(false)
    }
  }

  async function del() {
    if (!app || busy) return
    if (!window.confirm(`Delete "${app.name}"? This permanently removes the application and its approvals. This cannot be undone.`)) return
    setBusy(true); setError('')
    try {
      await api.del(`/api/applications/${app.application_id}`)
      navigate('/applications')
    } catch (e) {
      setError(e instanceof ApiException ? e.body.detail : 'Delete failed.')
      setBusy(false)
    }
  }

  async function decide(decision_code: string) {
    if (!appr || busy) return
    setBusy(true); setError('')
    try {
      const updated = await api.post<ApprovalRequest>(`/api/approvals/${appr.approval_request_id}/signoff`, { decision_code, comment: comment || null })
      setAppr(updated); setComment('')
      const fresh = await api.get<Application>(`/api/applications/${app!.application_id}`) // status may have rolled up
      setApp(fresh)
    } catch (e) {
      setError(e instanceof ApiException ? e.body.detail : 'Sign-off failed.')
    } finally {
      setBusy(false)
    }
  }

  // derived risk profile (declared perimeter — not a governed AI risk tier)
  const sensitivity = { label: labelOf(ref?.data_classifications, app.data_classification_code), tone: SENSITIVITY_TONE[app.data_classification_code] ?? 'neutral' }

  return (
    <div className="canvas-pad">
      {/* Identity band */}
      <div className="page-head">
        <div>
          <div className="page-head__title l-cluster">
            {app.name} <span className="tla">{app.code}</span>
            <ReviewBadge app={app} quiet />
          </div>
          <div className="page-head__sub">{app.description}</div>
          <div className="page-head__sub">Owner: {app.business_owner_name ?? '—'}{owned ? ' · you' : ''} · {labelOf(ref?.lines_of_business, app.line_of_business_code)} · onboarded {onboarded}</div>
        </div>
      </div>

      <div className="aw-body">
        <div className="tabs aw-tabs" role="tablist">
          {TABS.map((t) => (
            <button key={t.key} role="tab" aria-selected={tab === t.key} className={`tab${tab === t.key ? ' is-active' : ''}`} onClick={() => openTab(t.key)}>
              {t.label}
            </button>
          ))}
        </div>

        <div className="aw-main">
          {tab === 'compliance' && (
            <div className="aw-tabpanel card">
              <div className="kv">
                <span className="kv__k">Data classification</span><span className="kv__v">{sensitivity.label} <span className="u-text-tertiary">(ceiling)</span></span>
                <span className="kv__k">Frameworks</span><span className="kv__v">{app.regulatory_framework_codes.map((c) => <span key={c} className="chip chip--static">{labelOf(ref?.frameworks, c)}</span>)}</span>
                <span className="kv__k">Governance domains</span><span className="kv__v">{app.governance_domain_codes.map((c) => <span key={c} className="chip chip--static">{labelOf(ref?.governance_domains, c)}</span>)}</span>
                <span className="kv__k">Consumer impact</span><span className="kv__v">Decisions affecting consumers {yn(app.affects_consumers)} · PII/PHI {yn(app.processes_pii)} · Consumer-facing {yn(app.consumer_facing)}</span>
                <span className="kv__k">Jurisdictions</span><span className="kv__v">{app.jurisdiction_codes.map((c) => <span key={c} className="chip chip--static">{labelOf(ref?.jurisdictions, c)}</span>)}</span>
              </div>
            </div>
          )}

          {tab === 'ownership' && (
            <div className="aw-tabpanel card">
              <div className="kv">
                <span className="kv__k">Business owner</span><span className="kv__v">{app.business_owner_name ?? '—'}{owned ? ' · you' : ''}</span>
                <span className="kv__k">App team</span><span className="kv__v u-text-tertiary">No additional members yet (people directory coming later).</span>
              </div>
            </div>
          )}

          {tab === 'usecases' && (
            <div className="aw-tabpanel card">
              <div className="l-cluster">
                <div className="rail-panel__title">Use cases</div>
                <span className="l-spacer" />
                {app.application_status_code === 'active' && canDo('create_intake') && (
                  <button className="btn btn--secondary btn--md" onClick={() => navigate(`/applications/${app.application_id}/intakes/new`)}>New intake</button>
                )}
              </div>
              {intakes.length === 0 ? (
                <div className="empty-state">
                  <div className="empty-state__title">No use cases yet</div>
                  <div className="empty-state__body">
                    {app.application_status_code === 'active'
                      ? 'Intakes are the AI use cases governed under this application.'
                      : 'Use cases can be added once this application is active (onboarding approved).'}
                  </div>
                  {app.application_status_code === 'active' && canDo('create_intake') && (
                    <div className="empty-state__actions">
                      <button className="btn btn--primary btn--md" onClick={() => navigate(`/applications/${app.application_id}/intakes/new`)}>New intake</button>
                    </div>
                  )}
                </div>
              ) : (
                <div className="kv">
                  {intakes.map((i) => (
                    <Fragment key={i.intake_id}>
                      <span className="kv__k"><Badge table="intake_status" code={i.intake_status_code} /></span>
                      <span className="kv__v"><span className="breadcrumb__item" onClick={() => navigate(`/intakes/${i.intake_id}`)}>{i.title}</span></span>
                    </Fragment>
                  ))}
                </div>
              )}
            </div>
          )}
        </div>

        {/* Right rail — always visible */}
        <aside className="aw-rail">
          <div className="card">
            <div className="rail-panel__title">Risk profile</div>
            <div className="rail-row"><span className="rail-row__k">Data sensitivity</span><span className="rail-row__v"><span className="badge badge--sm" data-tone={sensitivity.tone}><span className="badge__dot" /><span className="badge__label">{sensitivity.label}</span></span></span></div>
            <div className="rail-row"><span className="rail-row__k">Consumer impact</span><span className="rail-row__v"><span className="badge badge--sm" data-tone={app.affects_consumers ? 'warning' : 'neutral'}><span className="badge__dot" /><span className="badge__label">{app.affects_consumers ? (app.consumer_facing ? 'Decisions · facing' : 'Decisions') : app.consumer_facing ? 'Consumer-facing' : 'None'}</span></span></span></div>
            <div className="rail-row"><span className="rail-row__k">Privacy</span><span className="rail-row__v"><span className="badge badge--sm" data-tone={app.processes_pii ? 'warning' : 'neutral'}><span className="badge__dot" /><span className="badge__label">{app.processes_pii ? 'PII / PHI' : 'None'}</span></span></span></div>
            <div className="rail-row"><span className="rail-row__k">Frameworks</span><span className="rail-row__v">{app.regulatory_framework_codes.length}</span></div>
            <div className="rail-row"><span className="rail-row__k">Jurisdictions</span><span className="rail-row__v">{app.jurisdiction_codes.length}</span></div>
            <div className="rail-row"><span className="rail-row__k">Governance domains</span><span className="rail-row__v">{app.governance_domain_codes.length}</span></div>
          </div>

          <div className="card">
            <div className="rail-panel__title">Governance &amp; approval</div>
            {appr ? (
              <>
                <div className="appr">
                  {appr.required_roles.map((role) => {
                    const s = appr.signoffs.find((x) => x.signed_as_role_code === role)
                    const mod = !s ? 'wait' : s.decision_code === 'approved' ? 'done' : s.decision_code === 'rejected' ? 'rejected' : 'wait'
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
                    {!allReviewed && <span className="input-hint">Open every tab to review before deciding.</span>}
                    {error && <span className="input-error-text">{error}</span>}
                    <button className="btn btn--positive btn--md" disabled={!allReviewed || busy} onClick={() => decide('approved')}>
                      <svg className="icon icon--sm" aria-hidden="true"><use href="#i-approve" /></svg>{busy ? 'Submitting…' : 'Approve'}
                    </button>
                    <button className="btn btn--secondary btn--md" disabled={!allReviewed || busy || !comment.trim()} onClick={() => decide('requested_changes')}>Request changes</button>
                    <button className="btn btn--danger btn--md" disabled={!allReviewed || busy || !comment.trim()} onClick={() => decide('rejected')}>Reject</button>
                  </div>
                ) : (
                  <div className="rail-actions">
                    {outcome ? (
                      <p className="input-error-text"><b>{outcome.label}.</b>{outcome.comment ? ` ${outcome.comment}` : ''}</p>
                    ) : (
                      <p className="input-hint">{pending ? (iSigned ? 'You have recorded your decision.' : 'Awaiting the required sign-off(s).') : `This request is ${appr.status_code}.`}</p>
                    )}
                  </div>
                )}
              </>
            ) : (
              <p className="input-hint">Not submitted for approval.</p>
            )}
          </div>
        </aside>
      </div>

      {/* Application actions (owner/requester lifecycle) — kept out of the governance rail; the
          destructive Delete is separated to the far end. */}
      {(editBtn || cancelBtn || deleteBtn) && (
        <section className="section">
          <div className="section__head"><span className="eyebrow">Application actions</span></div>
          <div className="l-cluster">
            {editBtn}
            {cancelBtn}
            <span className="l-spacer" />
            {deleteBtn}
          </div>
        </section>
      )}

      {/* Derived history */}
      <details className="aw-hist">
        <summary><svg className="icon icon--sm" aria-hidden="true"><use href="#i-recent" /></svg>History of changes</summary>
        <div className="card">
          {history.map((h, i) => (
            <div className="tl-item" key={i}>
              <span className="tl-item__dot" />
              <div><div>{h.body}</div>{h.t && <div className="tl-item__time">{fmt(h.t)}</div>}</div>
            </div>
          ))}
        </div>
      </details>
    </div>
  )
}
