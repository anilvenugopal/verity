import { type FormEvent, useEffect, useState } from 'react'
import { useNavigate } from 'react-router-dom'
import { api, ApiException } from '@/api/client'
import { useSession } from '@/auth/useSession'
import './OnboardForm.css'

interface Code { code: string; label: string }
interface Ref {
  data_classifications: Code[]
  lines_of_business: Code[]
  frameworks: Code[]
  governance_domains: Code[]
  jurisdictions: Code[]
}

// Onboard a governed application (FR-016): single page, sections A–D, sticky action bar. Submits
// POST /applications (+ /submit to open the approval). Owner defaults to you (no people-search yet).
export function OnboardForm() {
  const navigate = useNavigate()
  const { principal } = useSession()
  const [ref, setRef] = useState<Ref | null>(null)
  const [name, setName] = useState('')
  const [code, setCode] = useState('')
  const [description, setDescription] = useState('')
  const [lob, setLob] = useState('')
  const [classification, setClassification] = useState('')
  const [frameworks, setFrameworks] = useState<Set<string>>(new Set())
  const [domains, setDomains] = useState<Set<string>>(new Set())
  const [jurisdictions, setJurisdictions] = useState<Set<string>>(new Set())
  const [affectsConsumers, setAffectsConsumers] = useState<boolean | null>(null)
  const [processesPii, setProcessesPii] = useState<boolean | null>(null)
  const [consumerFacing, setConsumerFacing] = useState<boolean | null>(null)
  const [justification, setJustification] = useState('')
  const [busy, setBusy] = useState(false)
  const [error, setError] = useState('')

  useEffect(() => {
    api.get<Ref>('/api/reference/onboarding').then(setRef).catch(() => setError('Could not load reference data.'))
  }, [])

  function toggle(set: Set<string>, setter: (s: Set<string>) => void, v: string) {
    const next = new Set(set)
    if (next.has(v)) next.delete(v)
    else next.add(v)
    setter(next)
  }

  const valid =
    name.trim() &&
    /^[A-Z]{3}$/.test(code) &&
    description.trim().length >= 20 &&
    classification &&
    frameworks.size > 0 &&
    domains.size > 0 &&
    jurisdictions.size > 0 &&
    affectsConsumers !== null &&
    processesPii !== null &&
    consumerFacing !== null &&
    justification.trim()

  async function submit(e: FormEvent, alsoSubmit: boolean) {
    e.preventDefault()
    if (!valid || !principal || busy) return
    setBusy(true)
    setError('')
    try {
      const app = await api.post<{ application_id: string }>('/api/applications', {
        code,
        name,
        description,
        line_of_business_code: lob || null,
        data_classification_code: classification,
        regulatory_framework_codes: [...frameworks],
        governance_domain_codes: [...domains],
        jurisdiction_codes: [...jurisdictions],
        business_owner_actor_id: principal.actor_id,
        initial_app_team: [],
        affects_consumers: affectsConsumers,
        processes_pii: processesPii,
        consumer_facing: consumerFacing,
        justification,
      })
      if (alsoSubmit) await api.post(`/api/applications/${app.application_id}/submit`, {})
      navigate('/applications')
    } catch (err) {
      setError(err instanceof ApiException ? err.body.detail : 'Submit failed.')
      setBusy(false)
    }
  }

  const multi = (codes: Code[], sel: Set<string>, setter: (s: Set<string>) => void, label: string) => (
    <div className="chip-group" role="group" aria-label={label}>
      {codes.map((c) => (
        <button key={c.code} type="button" role="checkbox" aria-checked={sel.has(c.code)}
                className={`chip${sel.has(c.code) ? ' is-selected' : ''}`} onClick={() => toggle(sel, setter, c.code)}>
          {c.label}
        </button>
      ))}
    </div>
  )
  const single = (codes: Code[], value: string, setter: (v: string) => void, label: string) => (
    <div className="chip-group" role="radiogroup" aria-label={label}>
      {codes.map((c) => (
        <button key={c.code} type="button" role="radio" aria-checked={value === c.code}
                className={`chip${value === c.code ? ' is-selected' : ''}`} onClick={() => setter(c.code)}>
          {c.label}
        </button>
      ))}
    </div>
  )
  const yesNo = (value: boolean | null, setter: (b: boolean) => void, label: string) => (
    <div className="chip-group" role="radiogroup" aria-label={label}>
      <button type="button" role="radio" aria-checked={value === true} className={`chip${value === true ? ' is-selected' : ''}`} onClick={() => setter(true)}>Yes</button>
      <button type="button" role="radio" aria-checked={value === false} className={`chip${value === false ? ' is-selected' : ''}`} onClick={() => setter(false)}>No</button>
    </div>
  )

  if (!ref) {
    return <div className="canvas-pad"><div className="card"><div className="empty-state"><div className="empty-state__body">{error || 'Loading…'}</div></div></div></div>
  }

  return (
    <form className="canvas-pad" onSubmit={(e) => submit(e, true)}>
      <div className="page-head">
        <div>
          <div className="page-head__title">Onboard application</div>
          <div className="page-head__sub">Register a business application under governance. This opens an approval — the application stays <strong>pending</strong> until AI Governance and the business owner sign off.</div>
        </div>
      </div>

      <div className="callout callout--info">
        <svg className="icon callout__icon" aria-hidden="true"><use href="#i-callout-info" /></svg>
        <div className="callout__body"><span className="callout__title">Governed action.</span> Identity (name + acronym) is permanent once approved; the compliance perimeter can change later via a governed change proposal.</div>
      </div>

      {/* A · Identity */}
      <section className="fsec">
        <div className="fsec__head"><span className="fsec__num">A</span><span className="fsec__title">Identity</span></div>
        <div className="field-grid">
          <div className="field">
            <div className="form-field">
              <label className="form-label" htmlFor="name">Name <span className="req">*</span></label>
              <input className="input" id="name" placeholder="Personal Auto Underwriting" value={name} onChange={(e) => setName(e.target.value)} />
              <span className="input-hint">Unique across the platform.</span>
            </div>
          </div>
          <div className="field">
            <div className="form-field">
              <label className="form-label" htmlFor="tla">Acronym (TLA) <span className="req">*</span></label>
              <input className="input input--mono" id="tla" maxLength={3} placeholder="PAU" value={code}
                     onChange={(e) => setCode(e.target.value.replace(/[^a-z]/gi, '').toUpperCase().slice(0, 3))} />
              <span className="input-hint">3 letters, uppercase, unique. <strong>Permanent once approved.</strong></span>
            </div>
          </div>
          <div className="field field-full">
            <div className="form-field">
              <label className="form-label" htmlFor="purpose">Purpose <span className="req">*</span></label>
              <textarea className="input" id="purpose" placeholder="What this application does and its intended use (min 20 chars)." value={description} onChange={(e) => setDescription(e.target.value)} />
              <span className="input-hint">Intended purpose — the baseline against which proportionate controls are judged.</span>
            </div>
          </div>
          <div className="field">
            <div className="form-field">
              <label className="form-label" htmlFor="lob">Line of business</label>
              <select className="input" id="lob" value={lob} onChange={(e) => setLob(e.target.value)}>
                <option value="">—</option>
                {ref.lines_of_business.map((c) => <option key={c.code} value={c.code}>{c.label}</option>)}
              </select>
              <span className="input-hint">For reporting &amp; routing. Optional.</span>
            </div>
          </div>
        </div>
      </section>

      {/* B · Ownership */}
      <section className="fsec">
        <div className="fsec__head"><span className="fsec__num">B</span><span className="fsec__title">Ownership &amp; accountability</span></div>
        <div className="field">
          <label className="form-label">Business owner <span className="req">*</span></label>
          <div className="proposer">
            <span className="avatar">{(principal?.display_name ?? '?').slice(0, 2).toUpperCase()}</span>
            {principal?.display_name} · you
            <span className="proposer__tag">defaults to the proposer (people-search coming later)</span>
          </div>
          <span className="input-hint">The accountable owner and a required approver. Defaults to you for now.</span>
        </div>
      </section>

      {/* C · Compliance context */}
      <section className="fsec">
        <div className="fsec__head"><span className="fsec__num">C</span><span className="fsec__title">Compliance context</span><span className="fsec__note">application-wide perimeter</span></div>
        <div className="field">
          <div className="sublabel">Data classification <span className="req">*</span></div>
          {single(ref.data_classifications, classification, setClassification, 'Data classification')}
          <span className="input-hint">App-wide ceiling. PII/PHI = Yes ⇒ at least Confidential.</span>
        </div>
        <div className="field">
          <div className="sublabel">Regulatory frameworks <span className="req">*</span></div>
          {multi(ref.frameworks, frameworks, setFrameworks, 'Regulatory frameworks')}
          <span className="input-hint">At least one — use an internal-only framework if no external regime applies.</span>
        </div>
        <div className="field">
          <div className="sublabel">Governance domains <span className="req">*</span></div>
          {multi(ref.governance_domains, domains, setDomains, 'Governance domains')}
        </div>
        <div className="field">
          <div className="sublabel">Consumer impact</div>
          <div className="flag-row">
            <div><div className="flag-row__text">Makes or informs automated decisions affecting consumers? <span className="req">*</span></div><div className="flag-row__hint">Triggers EU AI Act / CO SB21-169 / NAIC scrutiny.</div></div>
            {yesNo(affectsConsumers, setAffectsConsumers, 'Affects consumers')}
          </div>
          <div className="flag-row">
            <div><div className="flag-row__text">Processes PII / PHI? <span className="req">*</span></div><div className="flag-row__hint">Privacy obligations; ceiling ≥ Confidential.</div></div>
            {yesNo(processesPii, setProcessesPii, 'Processes PII')}
          </div>
          <div className="flag-row">
            <div><div className="flag-row__text">Consumer-facing? <span className="req">*</span></div><div className="flag-row__hint">Disclosure / transparency obligations.</div></div>
            {yesNo(consumerFacing, setConsumerFacing, 'Consumer facing')}
          </div>
        </div>
        <div className="field">
          <div className="sublabel">Jurisdictions of operation <span className="req">*</span></div>
          {multi(ref.jurisdictions, jurisdictions, setJurisdictions, 'Jurisdictions')}
        </div>
      </section>

      {/* D · Governance & approval */}
      <section className="fsec">
        <div className="fsec__head"><span className="fsec__num">D</span><span className="fsec__title">Governance &amp; approval</span></div>
        <div className="field">
          <div className="form-field">
            <label className="form-label" htmlFor="just">Justification <span className="req">*</span></label>
            <textarea className="input" id="just" placeholder="Why this application should be onboarded." value={justification} onChange={(e) => setJustification(e.target.value)} />
            <span className="input-hint">Recorded as the approval justification.</span>
          </div>
        </div>
      </section>

      {error && (
        <div className="field callout callout--error">
          <svg className="icon callout__icon" aria-hidden="true"><use href="#i-callout-info" /></svg>
          <div className="callout__body">{error}</div>
        </div>
      )}

      <div className="form-actions">
        <div className="form-actions__summary">Opens an approval · approvers: <b>AI Governance</b> + <b>Business Owner</b></div>
        <span className="l-spacer" />
        <button type="button" className="btn btn--ghost btn--md" onClick={() => navigate('/applications')}>Cancel</button>
        <button type="button" className="btn btn--secondary btn--md" disabled={!valid || busy} onClick={(e) => submit(e, false)}>Save draft</button>
        <button type="submit" className="btn btn--primary btn--md" disabled={!valid || busy}>
          {busy ? 'Submitting…' : 'Submit for approval'}
        </button>
      </div>
    </form>
  )
}
