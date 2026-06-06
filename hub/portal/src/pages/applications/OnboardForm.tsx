import { type FormEvent, useEffect, useMemo, useState } from 'react'
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

// Onboard a governed application (FR-016): single page, sections A–D, sticky action bar. Required
// fields are surfaced industry-style — a per-field marker, a live "what's left" count, inline errors
// after a blur/attempt, and an error summary on submit that focuses the first gap (no silently
// disabled button). Submits POST /applications (+ /submit to open the approval).
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
  const [attempted, setAttempted] = useState(false)
  const [touched, setTouched] = useState<Set<string>>(new Set())

  useEffect(() => {
    api.get<Ref>('/api/reference/onboarding').then(setRef).catch(() => setError('Could not load reference data.'))
  }, [])

  function toggle(set: Set<string>, setter: (s: Set<string>) => void, v: string) {
    const next = new Set(set)
    if (next.has(v)) next.delete(v)
    else next.add(v)
    setter(next)
  }
  const touch = (k: string) => setTouched((t) => new Set(t).add(k))

  // One source of truth for required-field validity — drives markers, inline errors, the summary and
  // the live count. (Transfers wholesale to the tabbed create-mode in the next increment.)
  const checks = useMemo(
    () => [
      { key: 'name', label: 'Name', msg: 'Enter a name.', ok: !!name.trim() },
      { key: 'tla', label: 'Acronym (TLA)', msg: '3 uppercase letters.', ok: /^[A-Z]{3}$/.test(code) },
      { key: 'purpose', label: 'Purpose', msg: 'At least 20 characters.', ok: description.trim().length >= 20 },
      { key: 'classification', label: 'Data classification', msg: 'Select a classification.', ok: !!classification },
      { key: 'frameworks', label: 'Regulatory frameworks', msg: 'Select at least one.', ok: frameworks.size > 0 },
      { key: 'domains', label: 'Governance domains', msg: 'Select at least one.', ok: domains.size > 0 },
      { key: 'affectsConsumers', label: 'Consumer-decision flag', msg: 'Select Yes or No.', ok: affectsConsumers !== null },
      { key: 'processesPii', label: 'PII / PHI flag', msg: 'Select Yes or No.', ok: processesPii !== null },
      { key: 'consumerFacing', label: 'Consumer-facing flag', msg: 'Select Yes or No.', ok: consumerFacing !== null },
      { key: 'jurisdictions', label: 'Jurisdictions', msg: 'Select at least one.', ok: jurisdictions.size > 0 },
      { key: 'justification', label: 'Justification', msg: 'Enter a justification.', ok: !!justification.trim() },
    ],
    [name, code, description, classification, frameworks, domains, jurisdictions, affectsConsumers, processesPii, consumerFacing, justification],
  )
  const missing = checks.filter((c) => !c.ok)
  const valid = missing.length === 0
  const okOf = (k: string) => checks.find((c) => c.key === k)?.ok ?? true
  const msgOf = (k: string) => checks.find((c) => c.key === k)?.msg ?? ''
  const showErr = (k: string) => (attempted || touched.has(k)) && !okOf(k)
  const Err = ({ k }: { k: string }) => (showErr(k) ? <span className="input-error-text">{msgOf(k)}</span> : null)

  function focusField(key: string) {
    document.getElementById(`f-${key}`)?.scrollIntoView({ block: 'center', behavior: 'smooth' })
    ;(document.getElementById(key) as HTMLElement | null)?.focus?.()
  }

  async function submit(e: FormEvent, alsoSubmit: boolean) {
    e.preventDefault()
    if (busy || !principal) return
    if (!valid) {
      setAttempted(true)
      focusField(missing[0].key)
      return
    }
    setBusy(true)
    setError('')
    try {
      const app = await api.post<{ application_id: string }>('/api/applications', {
        code, name, description,
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
      navigate(`/applications/${app.application_id}`) // into the workspace (shows the governance rail)
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
    <form className="canvas-pad" onSubmit={(e) => submit(e, true)} noValidate>
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
          <div className="field" id="f-name">
            <div className="form-field">
              <label className="form-label is-required" htmlFor="name">Name</label>
              <input className={`input${showErr('name') ? ' input--error' : ''}`} id="name" placeholder="Personal Auto Underwriting" value={name} onChange={(e) => setName(e.target.value)} onBlur={() => touch('name')} />
              <span className="input-hint">Unique across the platform.</span>
              <Err k="name" />
            </div>
          </div>
          <div className="field" id="f-tla">
            <div className="form-field">
              <label className="form-label is-required" htmlFor="tla">Acronym (TLA)</label>
              <input className={`input input--mono${showErr('tla') ? ' input--error' : ''}`} id="tla" maxLength={3} placeholder="PAU" value={code}
                     onChange={(e) => setCode(e.target.value.replace(/[^a-z]/gi, '').toUpperCase().slice(0, 3))} onBlur={() => touch('tla')} />
              <span className="input-hint">3 letters, uppercase, unique. <strong>Permanent once approved.</strong></span>
              <Err k="tla" />
            </div>
          </div>
          <div className="field field-full" id="f-purpose">
            <div className="form-field">
              <label className="form-label is-required" htmlFor="purpose">Purpose</label>
              <textarea className={`input${showErr('purpose') ? ' input--error' : ''}`} id="purpose" placeholder="What this application does and its intended use (min 20 chars)." value={description} onChange={(e) => setDescription(e.target.value)} onBlur={() => touch('purpose')} />
              <span className="input-hint">Intended purpose — the baseline against which proportionate controls are judged.</span>
              <Err k="purpose" />
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
          <label className="form-label is-required">Business owner</label>
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
        <div className="field" id="f-classification">
          <div className="sublabel is-required">Data classification</div>
          {single(ref.data_classifications, classification, setClassification, 'Data classification')}
          <span className="input-hint">App-wide ceiling. PII/PHI = Yes ⇒ at least Confidential.</span>
          <Err k="classification" />
        </div>
        <div className="field" id="f-frameworks">
          <div className="sublabel is-required">Regulatory frameworks</div>
          {multi(ref.frameworks, frameworks, setFrameworks, 'Regulatory frameworks')}
          <span className="input-hint">At least one — use an internal-only framework if no external regime applies.</span>
          <Err k="frameworks" />
        </div>
        <div className="field" id="f-domains">
          <div className="sublabel is-required">Governance domains</div>
          {multi(ref.governance_domains, domains, setDomains, 'Governance domains')}
          <Err k="domains" />
        </div>
        <div className="field">
          <div className="sublabel">Consumer impact</div>
          <div className="flag-row" id="f-affectsConsumers">
            <div><div className="flag-row__text">Makes or informs automated decisions affecting consumers? <span className="req">*</span></div><div className="flag-row__hint">Triggers EU AI Act / CO SB21-169 / NAIC scrutiny.</div><Err k="affectsConsumers" /></div>
            {yesNo(affectsConsumers, setAffectsConsumers, 'Affects consumers')}
          </div>
          <div className="flag-row" id="f-processesPii">
            <div><div className="flag-row__text">Processes PII / PHI? <span className="req">*</span></div><div className="flag-row__hint">Privacy obligations; ceiling ≥ Confidential.</div><Err k="processesPii" /></div>
            {yesNo(processesPii, setProcessesPii, 'Processes PII')}
          </div>
          <div className="flag-row" id="f-consumerFacing">
            <div><div className="flag-row__text">Consumer-facing? <span className="req">*</span></div><div className="flag-row__hint">Disclosure / transparency obligations.</div><Err k="consumerFacing" /></div>
            {yesNo(consumerFacing, setConsumerFacing, 'Consumer facing')}
          </div>
        </div>
        <div className="field" id="f-jurisdictions">
          <div className="sublabel is-required">Jurisdictions of operation</div>
          {multi(ref.jurisdictions, jurisdictions, setJurisdictions, 'Jurisdictions')}
          <Err k="jurisdictions" />
        </div>
      </section>

      {/* D · Governance & approval */}
      <section className="fsec">
        <div className="fsec__head"><span className="fsec__num">D</span><span className="fsec__title">Governance &amp; approval</span></div>
        <div className="field" id="f-justification">
          <div className="form-field">
            <label className="form-label is-required" htmlFor="justification">Justification</label>
            <textarea className={`input${showErr('justification') ? ' input--error' : ''}`} id="justification" placeholder="Why this application should be onboarded." value={justification} onChange={(e) => setJustification(e.target.value)} onBlur={() => touch('justification')} />
            <span className="input-hint">Recorded as the approval justification.</span>
            <Err k="justification" />
          </div>
        </div>
      </section>

      {attempted && !valid && (
        <div className="callout callout--error">
          <svg className="icon callout__icon" aria-hidden="true"><use href="#i-callout-warning" /></svg>
          <div className="callout__body">
            <span className="callout__title">{missing.length} required field{missing.length > 1 ? 's' : ''} need attention.</span>
            <div className="l-cluster">
              {missing.map((m) => (
                <button key={m.key} type="button" className="chip chip--static" onClick={() => focusField(m.key)}>{m.label}</button>
              ))}
            </div>
          </div>
        </div>
      )}

      {error && (
        <div className="field callout callout--error">
          <svg className="icon callout__icon" aria-hidden="true"><use href="#i-callout-info" /></svg>
          <div className="callout__body">{error}</div>
        </div>
      )}

      <div className="form-actions">
        <div className="form-actions__summary">
          {valid
            ? <>Opens an approval · approvers: <b>AI Governance</b> + <b>Business Owner</b></>
            : <>{missing.length} required field{missing.length > 1 ? 's' : ''} remaining</>}
        </div>
        <span className="l-spacer" />
        <button type="button" className="btn btn--ghost btn--md" onClick={() => navigate('/applications')}>Cancel</button>
        <button type="button" className="btn btn--secondary btn--md" disabled={busy} onClick={(e) => submit(e, false)}>Save draft</button>
        <button type="submit" className="btn btn--primary btn--md" disabled={busy}>
          {busy ? 'Submitting…' : 'Submit for approval'}
        </button>
      </div>
    </form>
  )
}
