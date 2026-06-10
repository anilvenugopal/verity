import { Fragment, type FormEvent, useEffect, useMemo, useState } from 'react'
import { useNavigate, useParams } from 'react-router-dom'
import { api, ApiException } from '@/api/client'
import { useSession } from '@/auth/useSession'
import type { ApprovalRequest, Intake, Requirement } from '@/api/types'
import { isIntakeRevisable } from '@/api/types'
import { Badge } from '@/components/Badge'
import '../applications/ApplicationWorkspace.css' // shared workspace layout (band/tabs/rail/footer)

// The fixed requirement-kind vocabulary (reference.requirement_kind; not a badge table, rendered as a
// chip). Kept client-side as a labelled list for the add-requirement selector.
const REQUIREMENT_KINDS = [
  { code: 'business', label: 'Business' },
  { code: 'functional', label: 'Functional' },
  { code: 'non_functional', label: 'Non-functional' },
  { code: 'compliance', label: 'Compliance' },
]
const kindLabel = (c: string) => REQUIREMENT_KINDS.find((k) => k.code === c)?.label ?? c

const ROLE_LABEL: Record<string, string> = {
  ai_governance: 'AI Governance', business_owner: 'Business Owner', security: 'Security',
  compliance: 'Compliance', legal: 'Legal', model_risk: 'Model Risk', privacy: 'Privacy',
}
const roleLabel = (c: string) => ROLE_LABEL[c] ?? c.replace(/_/g, ' ').replace(/\b\w/g, (m) => m.toUpperCase())
const DECISION_LABEL: Record<string, string> = {
  approved: 'Approved', rejected: 'Rejected', requested_changes: 'Requested changes', abstained: 'Abstained',
}
const fmt = (iso?: string | null) =>
  iso ? new Date(iso).toLocaleString(undefined, { day: 'numeric', month: 'short', year: 'numeric', hour: '2-digit', minute: '2-digit' }) : ''

// Intake detail — the use-case workspace. Mirrors ApplicationWorkspace's shape (identity band + main +
// always-visible right rail + an Intake-actions footer) so the experience is familiar. Phase 7 covers
// requirements + the lifecycle footer (Edit / Cancel request / Delete, parity with applications);
// the assessment tabs (Phase 8) and the interactive sign-off gate + submit (Phase 9) fold in next.
export function IntakeDetail() {
  const { id } = useParams<{ id: string }>()
  const navigate = useNavigate()
  const { canDo } = useSession()
  const [intake, setIntake] = useState<Intake | null>(null)
  const [reqs, setReqs] = useState<Requirement[]>([])
  const [appr, setAppr] = useState<ApprovalRequest | null>(null)
  const [appName, setAppName] = useState<string | null>(null)
  const [notFound, setNotFound] = useState(false)
  const [busy, setBusy] = useState(false)
  const [error, setError] = useState('')
  // add-requirement form
  const [adding, setAdding] = useState(false)
  const [kind, setKind] = useState('functional')
  const [rTitle, setRTitle] = useState('')
  const [rBody, setRBody] = useState('')

  function loadApproval(intakeId: string) {
    api.get<ApprovalRequest>(`/api/intakes/${intakeId}/approval`).then(setAppr).catch(() => setAppr(null)) // 404 = not submitted
  }

  useEffect(() => {
    if (!id) return
    api.get<Intake>(`/api/intakes/${id}`).then((i) => {
      setIntake(i)
      api.get<{ name: string }>(`/api/applications/${i.application_id}`).then((a) => setAppName(a.name)).catch(() => undefined)
    }).catch((e) => { if (e instanceof ApiException && e.status === 404) setNotFound(true) })
    api.get<Requirement[]>(`/api/intakes/${id}/requirements`).then(setReqs).catch(() => undefined)
    loadApproval(id)
  }, [id])

  const history = useMemo(() => {
    if (!intake) return []
    const items: { t: string | null; body: string }[] = [{ t: intake.created_at, body: 'Intake proposed' }]
    if (appr) {
      items.push({ t: appr.created_at, body: 'Submitted for approval' })
      for (const s of appr.signoffs) {
        items.push({ t: s.created_at ?? null, body: `${roleLabel(s.signed_as_role_code)} · ${DECISION_LABEL[s.decision_code] ?? s.decision_code}` })
      }
    }
    return items.sort((a, b) => (a.t ?? '').localeCompare(b.t ?? ''))
  }, [intake, appr])

  if (notFound) {
    return (
      <div className="canvas-pad"><div className="card"><div className="empty-state">
        <div className="empty-state__title">Intake not found</div>
        <div className="empty-state__actions">
          <button className="btn btn--secondary btn--md" onClick={() => navigate('/applications')}>Back to applications</button>
        </div>
      </div></div></div>
    )
  }
  if (!intake) {
    return <div className="canvas-pad"><div className="card"><div className="empty-state"><div className="empty-state__body">Loading…</div></div></div></div>
  }

  const revisable = isIntakeRevisable(intake.intake_status_code)
  const pending = appr?.status_code === 'pending'
  const canEdit = revisable && canDo('edit_intake')
  const tierKnown = !!intake.ai_risk_tier_code
  const progress = tierKnown ? 'Tier computed' : 'Not started'

  async function addRequirement(e: FormEvent) {
    e.preventDefault()
    if (busy || !rTitle.trim() || !rBody.trim()) return
    setBusy(true); setError('')
    try {
      await api.post<Requirement>(`/api/intakes/${intake!.intake_id}/requirements`, {
        requirement_kind_code: kind, title: rTitle.trim(), body: rBody.trim(),
      })
      setReqs(await api.get<Requirement[]>(`/api/intakes/${intake!.intake_id}/requirements`))
      setRTitle(''); setRBody(''); setAdding(false)
    } catch (err) {
      setError(err instanceof ApiException ? err.body.detail : 'Could not add requirement.')
    } finally {
      setBusy(false)
    }
  }

  async function withdraw() {
    if (busy) return
    setBusy(true); setError('')
    try {
      setIntake(await api.post<Intake>(`/api/intakes/${intake!.intake_id}/withdraw`, {}))
      loadApproval(intake!.intake_id)
    } catch (err) {
      setError(err instanceof ApiException ? err.body.detail : 'Cancel failed.')
    } finally {
      setBusy(false)
    }
  }

  async function del() {
    if (busy) return
    if (!window.confirm(`Delete "${intake!.title}"? This permanently removes the intake and its requirements. This cannot be undone.`)) return
    setBusy(true); setError('')
    try {
      await api.del(`/api/intakes/${intake!.intake_id}`)
      navigate(`/applications/${intake!.application_id}`)
    } catch (err) {
      setError(err instanceof ApiException ? err.body.detail : 'Delete failed.')
      setBusy(false)
    }
  }

  const editBtn = canEdit && (
    <button className="btn btn--primary btn--md" onClick={() => navigate(`/intakes/${intake.intake_id}/edit`)}>Edit</button>
  )
  const cancelBtn = pending && canDo('edit_intake') && (
    <button className="btn btn--ghost btn--md" disabled={busy} onClick={withdraw}>Cancel request</button>
  )
  const deleteBtn = revisable && canDo('delete_intake') && (
    <button className="btn btn--danger btn--md" disabled={busy} onClick={del}>Delete</button>
  )

  return (
    <div className="canvas-pad">
      {/* Identity band */}
      <div className="page-head">
        <div>
          <div className="page-head__title l-cluster">
            {intake.title}
            <Badge table="intake_status" code={intake.intake_status_code} quiet />
            {intake.ai_risk_tier_code && <Badge table="ai_risk_tier" code={intake.ai_risk_tier_code} quiet />}
          </div>
          {intake.description && <div className="page-head__sub">{intake.description}</div>}
          <div className="breadcrumb">
            <span className="breadcrumb__item" onClick={() => navigate(`/applications/${intake.application_id}`)}>{appName ?? 'Application'}</span>
            <span className="breadcrumb__sep">›</span>
            <span className="breadcrumb__item breadcrumb__item--current">{intake.title}</span>
          </div>
        </div>
      </div>

      <div className="aw-body">
        <div className="aw-main">
          <div className="aw-tabpanel card">
            <div className="rail-panel__title">Requirements</div>
            {reqs.length === 0 ? (
              <p className="input-hint">No requirements yet. Capture the business, functional, and compliance requirements for this use case.</p>
            ) : (
              <div className="kv">
                {reqs.map((r) => (
                  <Fragment key={r.intake_requirement_id}>
                    <span className="kv__k"><span className="chip chip--static">{kindLabel(r.requirement_kind_code)}</span></span>
                    <span className="kv__v"><strong>{r.title}</strong><div className="u-text-tertiary">{r.body}</div></span>
                  </Fragment>
                ))}
              </div>
            )}

            {canEdit && (
              adding ? (
                <form className="rail-actions" onSubmit={addRequirement}>
                  <div className="form-field">
                    <label className="form-label" htmlFor="req-kind">Kind</label>
                    <select className="input" id="req-kind" value={kind} onChange={(e) => setKind(e.target.value)}>
                      {REQUIREMENT_KINDS.map((k) => <option key={k.code} value={k.code}>{k.label}</option>)}
                    </select>
                  </div>
                  <div className="form-field">
                    <label className="form-label is-required" htmlFor="req-title">Title</label>
                    <input className="input" id="req-title" placeholder="Short requirement name" value={rTitle} onChange={(e) => setRTitle(e.target.value)} />
                  </div>
                  <div className="form-field">
                    <label className="form-label is-required" htmlFor="req-body">Detail</label>
                    <textarea className="input" id="req-body" placeholder="What the requirement entails." value={rBody} onChange={(e) => setRBody(e.target.value)} />
                  </div>
                  {error && <span className="input-error-text">{error}</span>}
                  <div className="l-cluster">
                    <button type="submit" className="btn btn--primary btn--md" disabled={busy || !rTitle.trim() || !rBody.trim()}>{busy ? 'Adding…' : 'Add requirement'}</button>
                    <button type="button" className="btn btn--ghost btn--md" disabled={busy} onClick={() => { setAdding(false); setError('') }}>Cancel</button>
                  </div>
                </form>
              ) : (
                <div className="l-cluster">
                  <button className="btn btn--secondary btn--md" onClick={() => setAdding(true)}>Add requirement</button>
                </div>
              )
            )}
          </div>
        </div>

        {/* Right rail — always visible */}
        <aside className="aw-rail">
          <div className="card">
            <div className="rail-panel__title">Risk profile</div>
            <div className="rail-row"><span className="rail-row__k">Risk tier</span><span className="rail-row__v">{intake.ai_risk_tier_code ? <Badge table="ai_risk_tier" code={intake.ai_risk_tier_code} size="sm" /> : <span className="u-text-tertiary">Not assessed</span>}</span></div>
            <div className="rail-row"><span className="rail-row__k">Assessment</span><span className="rail-row__v">{progress}</span></div>
            <div className="rail-row"><span className="rail-row__k">Requirements</span><span className="rail-row__v">{reqs.length}</span></div>
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
                <p className="input-hint">{pending ? 'Awaiting the required sign-off(s).' : `This request is ${appr.status_code}.`}</p>
              </>
            ) : (
              <p className="input-hint">Not submitted for approval. Complete the assessment, then submit.</p>
            )}
          </div>
        </aside>
      </div>

      {/* Intake actions (requester / app-team lifecycle) — kept out of the governance rail; the
          destructive Delete is separated to the far end. Mirrors the application workspace footer. */}
      {(editBtn || cancelBtn || deleteBtn) && (
        <section className="section">
          <div className="section__head"><span className="eyebrow">Intake actions</span></div>
          <div className="l-cluster">
            {editBtn}
            {cancelBtn}
            <span className="l-spacer" />
            {deleteBtn}
          </div>
          {error && <span className="input-error-text">{error}</span>}
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
