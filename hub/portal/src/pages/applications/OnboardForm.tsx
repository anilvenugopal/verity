import { type FormEvent, useEffect, useMemo, useState } from 'react'
import { useNavigate, useParams } from 'react-router-dom'
import { api, ApiException } from '@/api/client'
import { useSession } from '@/auth/useSession'
import { useToast } from '@/shell/useToast'
import type { Application } from '@/api/types'
import './ApplicationWorkspace.css' // shared workspace layout (band/tabs/rail)
import './OnboardForm.css'

interface Code { code: string; label: string }
interface Ref {
  data_classifications: Code[]
  lines_of_business: Code[]
  frameworks: Code[]
  governance_domains: Code[]
  jurisdictions: Code[]
}

// data-classification ceiling → at-a-glance sensitivity tone (mirrors the workspace view)
const SENSITIVITY_TONE: Record<string, string> = {
  tier4_pii_restricted: 'negative', tier3_confidential: 'warning', tier2_internal: 'neutral', tier1_public: 'neutral',
}
const labelOf = (codes: Code[] | undefined, code: string) => codes?.find((c) => c.code === code)?.label || '—'

const TABS = [
  { key: 'compliance', label: 'Compliance' },
  { key: 'ownership', label: 'Ownership & team' },
]
// which tab a required field lives on (undefined = the always-visible Identity card or the rail)
const FIELD_TAB: Record<string, string> = {
  classification: 'compliance', frameworks: 'compliance', domains: 'compliance',
  affectsConsumers: 'compliance', processesPii: 'compliance', consumerFacing: 'compliance', jurisdictions: 'compliance',
}

// Onboard an application (FR-016) — create mode of the application workspace: Identity card on top,
// Compliance/Ownership tabs (Prev/Next, error markers), and a right rail with a live Risk Profile +
// Governance & approval (justification + actions). Required fields surfaced industry-style: per-field
// marker, live count, inline errors + a focusing summary on attempt (no silently disabled button).
export function OnboardForm() {
  const navigate = useNavigate()
  const { success } = useToast()
  const { id } = useParams<{ id: string }>() // set => edit mode (pending app), unset => create
  const editing = !!id
  const { principal } = useSession()
  const [ref, setRef] = useState<Ref | null>(null)
  const [ownerId, setOwnerId] = useState('') // business owner (self on create; loaded on edit)
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
  const [tab, setTab] = useState('compliance')
  const [attempted, setAttempted] = useState(false)
  const [touched, setTouched] = useState<Set<string>>(new Set())

  useEffect(() => {
    api.get<Ref>('/api/reference/onboarding').then(setRef).catch(() => setError('Could not load reference data.'))
  }, [])

  // Edit mode: prefill from the pending application. Justification is not persisted, so it starts
  // blank and must be re-entered (a known backend gap).
  useEffect(() => {
    if (!id) return
    api.get<Application>(`/api/applications/${id}`).then((a) => {
      setName(a.name); setCode(a.code); setDescription(a.description); setLob(a.line_of_business_code ?? '')
      setClassification(a.data_classification_code)
      setFrameworks(new Set(a.regulatory_framework_codes)); setDomains(new Set(a.governance_domain_codes))
      setJurisdictions(new Set(a.jurisdiction_codes))
      setAffectsConsumers(a.affects_consumers); setProcessesPii(a.processes_pii); setConsumerFacing(a.consumer_facing)
      setOwnerId(a.business_owner_actor_id)
    }).catch(() => setError('Could not load the application.'))
  }, [id])

  function toggle(set: Set<string>, setter: (s: Set<string>) => void, v: string) {
    const next = new Set(set)
    if (next.has(v)) next.delete(v)
    else next.add(v)
    setter(next)
  }
  const touch = (k: string) => setTouched((t) => new Set(t).add(k))

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
  // a tab's marker: error if attempted and it has a missing field, else done once attempted
  const tabState = (tk: string) => {
    if (!attempted) return null
    const keys = Object.keys(FIELD_TAB).filter((k) => FIELD_TAB[k] === tk)
    if (keys.length === 0) return null
    return keys.some((k) => !okOf(k)) ? 'error' : 'done'
  }

  function focusField(key: string) {
    const t = FIELD_TAB[key]
    const switching = !!t && t !== tab
    if (switching) setTab(t)
    setTimeout(() => {
      document.getElementById(`f-${key}`)?.scrollIntoView({ block: 'center', behavior: 'smooth' })
      ;(document.getElementById(key) as HTMLElement | null)?.focus?.()
    }, switching ? 60 : 0)
  }

  async function submit(e: FormEvent, alsoSubmit: boolean) {
    e.preventDefault()
    if (busy || !principal) return
    if (!valid) {
      setAttempted(true)
      focusField(missing[0]?.key ?? '')
      return
    }
    setBusy(true)
    setError('')
    const payload = {
      code, name, description,
      line_of_business_code: lob || null,
      data_classification_code: classification,
      regulatory_framework_codes: [...frameworks],
      governance_domain_codes: [...domains],
      jurisdiction_codes: [...jurisdictions],
      business_owner_actor_id: ownerId || principal.actor_id,
      initial_app_team: [],
      affects_consumers: affectsConsumers,
      processes_pii: processesPii,
      consumer_facing: consumerFacing,
      justification,
    }
    try {
      const appId = editing
        ? (await api.put<{ application_id: string }>(`/api/applications/${id}`, payload)).application_id
        : (await api.post<{ application_id: string }>('/api/applications', payload)).application_id
      if (alsoSubmit) {
        await api.post(`/api/applications/${appId}/submit`, {})
        success('Application submitted for approval')
      } else {
        success(editing ? 'Application updated' : 'Application created')
      }
      navigate(`/applications/${appId}`) // into the workspace
    } catch (err) {
      setError(err instanceof ApiException ? err.body.detail : 'Submit failed.')
      setBusy(false)
    }
  }

  const multi = (codes: Code[], sel: Set<string>, setter: (s: Set<string>) => void, label: string) => (
    <div className="chip-group" role="group" aria-label={label}>
      {codes.map((c) => (
        <button key={c.code} type="button" role="checkbox" aria-checked={sel.has(c.code)}
                className={`chip${sel.has(c.code) ? ' is-selected' : ''}`} onClick={() => toggle(sel, setter, c.code)}>{c.label}</button>
      ))}
    </div>
  )
  const single = (codes: Code[], value: string, setter: (v: string) => void, label: string) => (
    <div className="chip-group" role="radiogroup" aria-label={label}>
      {codes.map((c) => (
        <button key={c.code} type="button" role="radio" aria-checked={value === c.code}
                className={`chip${value === c.code ? ' is-selected' : ''}`} onClick={() => setter(c.code)}>{c.label}</button>
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

  // live risk profile (derived from current selections)
  const sens = { label: labelOf(ref.data_classifications, classification), tone: SENSITIVITY_TONE[classification] ?? 'neutral' }

  return (
    <form className="canvas-pad" onSubmit={(e) => submit(e, true)} noValidate>
      <div className="page-head">
        <div>
          <div className="page-head__title">{editing ? 'Edit application' : 'Onboard application'}</div>
          <div className="page-head__sub">{editing
            ? 'Revise this pending application and re-submit. Re-submitting opens a fresh approval.'
            : <>Register a business application under governance. This opens an approval — it stays <strong>pending</strong> until AI Governance (and the business owner) sign off.</>}</div>
        </div>
      </div>

      {/* Identity — basic info, above the tabs (mirrors the workspace band) */}
      <div className="card">
        <div className="rail-panel__title">Identity</div>
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
              <span className="input-hint">3 letters, uppercase. <strong>Permanent once approved.</strong></span>
              <Err k="tla" />
            </div>
          </div>
          <div className="field field-full" id="f-purpose">
            <div className="form-field">
              <label className="form-label is-required" htmlFor="purpose">Purpose</label>
              <textarea className={`input${showErr('purpose') ? ' input--error' : ''}`} id="purpose" placeholder="What this application does and its intended use (min 20 chars)." value={description} onChange={(e) => setDescription(e.target.value)} onBlur={() => touch('purpose')} />
              <span className="input-hint">The baseline against which proportionate controls are judged.</span>
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
      </div>

      <div className="aw-body">
        <div className="tabs aw-tabs" role="tablist">
          {TABS.map((t) => {
            const st = tabState(t.key)
            return (
              <button key={t.key} role="tab" aria-selected={tab === t.key} className={`tab${tab === t.key ? ' is-active' : ''}`} onClick={() => setTab(t.key)}>
                {t.label}{st && <span className={`tab__marker tab__marker--${st}`} />}
              </button>
            )
          })}
        </div>

        <div className="aw-main">
          {tab === 'compliance' && (
            <div className="aw-tabpanel card">
              <div className="field" id="f-classification">
                <div className="sublabel is-required">Data classification</div>
                {single(ref.data_classifications, classification, setClassification, 'Data classification')}
                <span className="input-hint">App-wide ceiling. PII/PHI = Yes ⇒ at least Confidential.</span>
                <Err k="classification" />
              </div>
              <div className="field" id="f-frameworks">
                <div className="sublabel is-required">Regulatory frameworks</div>
                {multi(ref.frameworks, frameworks, setFrameworks, 'Regulatory frameworks')}
                <span className="input-hint">At least one — use an internal-only framework if none external applies.</span>
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
                  <div><div className="flag-row__text">Automated decisions affecting consumers? <span className="req">*</span></div><div className="flag-row__hint">Triggers EU AI Act / CO SB21-169 / NAIC scrutiny.</div><Err k="affectsConsumers" /></div>
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
              <div className="field l-cluster">
                <span className="l-spacer" />
                <button type="button" className="btn btn--secondary btn--md" onClick={() => setTab('ownership')}>Next ›</button>
              </div>
            </div>
          )}

          {tab === 'ownership' && (
            <div className="aw-tabpanel card">
              <div className="field">
                <label className="form-label is-required">Business owner</label>
                <div className="proposer">
                  <span className="avatar">{(principal?.display_name ?? '?').slice(0, 2).toUpperCase()}</span>
                  {principal?.display_name} · you
                  <span className="proposer__tag">defaults to the proposer (people-search coming later)</span>
                </div>
                <span className="input-hint">The accountable owner and a required approver. Defaults to you for now.</span>
              </div>
              <div className="field l-cluster">
                <button type="button" className="btn btn--ghost btn--md" onClick={() => setTab('compliance')}>‹ Prev</button>
              </div>
            </div>
          )}
        </div>

        {/* Right rail — live risk profile + governance & approval (justification + actions) */}
        <aside className="aw-rail">
          <div className="card">
            <div className="rail-panel__title">Risk profile</div>
            <div className="rail-row"><span className="rail-row__k">Data sensitivity</span><span className="rail-row__v"><span className="badge badge--sm" data-tone={sens.tone}><span className="badge__dot" /><span className="badge__label">{sens.label}</span></span></span></div>
            <div className="rail-row"><span className="rail-row__k">Consumer impact</span><span className="rail-row__v"><span className="badge badge--sm" data-tone={affectsConsumers ? 'warning' : 'neutral'}><span className="badge__dot" /><span className="badge__label">{affectsConsumers ? (consumerFacing ? 'Decisions · facing' : 'Decisions') : consumerFacing ? 'Consumer-facing' : 'None'}</span></span></span></div>
            <div className="rail-row"><span className="rail-row__k">Privacy</span><span className="rail-row__v"><span className="badge badge--sm" data-tone={processesPii ? 'warning' : 'neutral'}><span className="badge__dot" /><span className="badge__label">{processesPii ? 'PII / PHI' : 'None'}</span></span></span></div>
            <div className="rail-row"><span className="rail-row__k">Frameworks</span><span className="rail-row__v">{frameworks.size}</span></div>
            <div className="rail-row"><span className="rail-row__k">Jurisdictions</span><span className="rail-row__v">{jurisdictions.size}</span></div>
            <div className="rail-row"><span className="rail-row__k">Governance domains</span><span className="rail-row__v">{domains.size}</span></div>
          </div>

          <div className="card">
            <div className="rail-panel__title">Governance &amp; approval</div>
            <div className="field" id="f-justification">
              <div className="form-field">
                <label className="form-label is-required" htmlFor="justification">Justification</label>
                <textarea className={`input${showErr('justification') ? ' input--error' : ''}`} id="justification" placeholder="Why this application should be onboarded." value={justification} onChange={(e) => setJustification(e.target.value)} onBlur={() => touch('justification')} />
                <Err k="justification" />
              </div>
            </div>
            <p className="input-hint">Submitting opens an approval · <b>AI Governance</b> + <b>Business Owner</b>.</p>

            {attempted && !valid && (
              <div className="field">
                <span className="input-error-text">{missing.length} required field{missing.length > 1 ? 's' : ''} remaining:</span>
                <div className="l-cluster">
                  {missing.map((m) => (
                    <button key={m.key} type="button" className="chip chip--static" onClick={() => focusField(m.key)}>{m.label}</button>
                  ))}
                </div>
              </div>
            )}
            {error && <div className="field"><span className="input-error-text">{error}</span></div>}

            <div className="rail-actions">
              <button type="submit" className="btn btn--primary btn--md" disabled={busy}>{busy ? 'Submitting…' : editing ? 'Re-submit for approval' : 'Submit for approval'}</button>
              <button type="button" className="btn btn--secondary btn--md" disabled={busy} onClick={(e) => submit(e, false)}>{editing ? 'Save changes' : 'Save draft'}</button>
              <button type="button" className="btn btn--ghost btn--md" onClick={() => navigate(editing ? `/applications/${id}` : '/applications')}>Cancel</button>
            </div>
          </div>
        </aside>
      </div>
    </form>
  )
}
