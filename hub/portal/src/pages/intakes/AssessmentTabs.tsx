import { type FormEvent, useEffect, useState } from 'react'
import { api, ApiException } from '@/api/client'
import type { AssessmentView } from '@/api/types'
import { Badge } from '@/components/Badge'

// The two shipped assessment sections (FR-026). This component owns the WHOLE draft (both sections)
// and persists the FULL snapshot on Save (FR-027: no partial PUT — the backend captures one SCD-2
// revision and recomputes the tier). IntakeDetail hoists the section choice to its main tabs and
// keeps this mounted across tab switches, so an in-progress draft survives. Read-only when !canEdit.

type Opt = { value: string; label: string }
const ROLE: Opt[] = [
  { value: 'assists', label: 'Assists a human' },
  { value: 'recommends_with_signoff', label: 'Recommends (human sign-off)' },
  { value: 'autonomous', label: 'Autonomous decision' },
]
const DOMAIN: Opt[] = [
  { value: 'underwriting', label: 'Underwriting' }, { value: 'pricing', label: 'Pricing' },
  { value: 'claims', label: 'Claims' }, { value: 'fraud', label: 'Fraud' },
  { value: 'marketing', label: 'Marketing' }, { value: 'servicing', label: 'Servicing' },
  { value: 'internal_ops', label: 'Internal operations' },
]
const POPULATION: Opt[] = [
  { value: 'internal_only', label: 'Internal only' },
  { value: 'brokers_agents', label: 'Brokers / agents' },
  { value: 'policyholders_consumers', label: 'Policyholders / consumers' },
  { value: 'vulnerable', label: 'Vulnerable populations' },
]
const IMPACT: Opt[] = [
  { value: 'negligible', label: 'Negligible' }, { value: 'financial', label: 'Financial' },
  { value: 'coverage_or_claim_denial', label: 'Coverage / claim denial' },
  { value: 'unfair_discriminatory', label: 'Unfair / discriminatory' }, { value: 'safety', label: 'Safety' },
]
const OVERSIGHT: Opt[] = [
  { value: 'none', label: 'None' }, { value: 'on_the_loop', label: 'On the loop' }, { value: 'in_the_loop', label: 'In the loop' },
]
const REVERSIBILITY: Opt[] = [
  { value: 'easily_reversible', label: 'Easily reversible' },
  { value: 'reversible_with_effort', label: 'Reversible with effort' },
  { value: 'irreversible', label: 'Irreversible' },
]
const SCALE: Opt[] = [
  { value: 'pilot', label: 'Pilot' }, { value: 'limited', label: 'Limited' }, { value: 'production_wide', label: 'Production-wide' },
]
const PII: Opt[] = [
  { value: 'none', label: 'None' }, { value: 'direct', label: 'Direct (name, SSN…)' },
  { value: 'indirect', label: 'Indirect / quasi-identifiers' }, { value: 'special_category', label: 'Special category' },
]

interface Impact {
  decision_role: string; decision_domain: string; affected_population: string; adverse_impact: string
  oversight_strategy: string; oversight_threshold: string
  reversibility: string; gdpr_art22: boolean | null; deployment_scale: string
}
interface Data {
  description: string; sources: string; data_classification_code: string; pii_presence: string
  sensitive_categories: string; lawful_basis: string; residency: string; retention: string; use: string
}
const EMPTY_IMPACT: Impact = {
  decision_role: '', decision_domain: '', affected_population: '', adverse_impact: '',
  oversight_strategy: '', oversight_threshold: '', reversibility: '', gdpr_art22: null, deployment_scale: '',
}
const EMPTY_DATA: Data = {
  description: '', sources: '', data_classification_code: '', pii_presence: '',
  sensitive_categories: '', lawful_basis: '', residency: '', retention: '', use: '',
}
const splitCsv = (s: string) => s.split(',').map((x) => x.trim()).filter(Boolean)
const joinCsv = (a: unknown) => (Array.isArray(a) ? a.join(', ') : '')

interface RefCode { code: string; label: string }

export function AssessmentTabs({
  intakeId, section, canEdit, onComputed,
}: {
  intakeId: string
  section: 'impact' | 'data' | null
  canEdit: boolean
  onComputed: () => void
}) {
  const [impact, setImpact] = useState<Impact>(EMPTY_IMPACT)
  const [data, setData] = useState<Data>(EMPTY_DATA)
  const [computed, setComputed] = useState<AssessmentView['computed']>(null)
  const [revision, setRevision] = useState<number | null>(null)
  const [classifications, setClassifications] = useState<RefCode[]>([])
  const [busy, setBusy] = useState(false)
  const [error, setError] = useState('')
  const [attempted, setAttempted] = useState(false)

  useEffect(() => {
    api.get<{ data_classifications: RefCode[] }>('/api/reference/onboarding').then((r) => setClassifications(r.data_classifications)).catch(() => undefined)
  }, [])

  useEffect(() => {
    api.get<AssessmentView>(`/api/intakes/${intakeId}/assessment`).then((v) => {
      const a = v.assessment as { ai_decision_impact?: Record<string, unknown>; data?: Record<string, unknown> }
      const ai = a.ai_decision_impact ?? {}
      const ho = (ai.human_oversight as Record<string, unknown> | undefined) ?? {}
      setImpact({
        decision_role: String(ai.decision_role ?? ''), decision_domain: String(ai.decision_domain ?? ''),
        affected_population: String(ai.affected_population ?? ''), adverse_impact: String(ai.adverse_impact ?? ''),
        oversight_strategy: String(ho.strategy ?? ''), oversight_threshold: String(ho.threshold ?? ''),
        reversibility: String(ai.reversibility ?? ''), gdpr_art22: typeof ai.gdpr_art22 === 'boolean' ? ai.gdpr_art22 : null,
        deployment_scale: String(ai.deployment_scale ?? ''),
      })
      const d = a.data ?? {}
      setData({
        description: String(d.description ?? ''), sources: joinCsv(d.sources), data_classification_code: String(d.data_classification_code ?? ''),
        pii_presence: String(d.pii_presence ?? ''), sensitive_categories: joinCsv(d.sensitive_categories),
        lawful_basis: String(d.lawful_basis ?? ''), residency: String(d.residency ?? ''), retention: String(d.retention ?? ''), use: String(d.use ?? ''),
      })
      setComputed(v.computed); setRevision(v.revision)
    }).catch(() => undefined) // 404 = not assessed yet (blank draft)
  }, [intakeId])

  const impactValid = !!(impact.decision_role && impact.decision_domain && impact.affected_population && impact.adverse_impact
    && impact.oversight_strategy && impact.reversibility && impact.deployment_scale) && impact.gdpr_art22 !== null
  const dataValid = !!(data.description.trim() && data.data_classification_code && data.pii_presence)
  const valid = impactValid && dataValid

  async function save(e: FormEvent) {
    e.preventDefault()
    if (busy || !canEdit) return
    if (!valid) { setAttempted(true); return }
    setBusy(true); setError('')
    const payload = {
      ai_decision_impact: {
        decision_role: impact.decision_role, decision_domain: impact.decision_domain,
        affected_population: impact.affected_population, adverse_impact: impact.adverse_impact,
        human_oversight: { strategy: impact.oversight_strategy, threshold: impact.oversight_threshold || null },
        reversibility: impact.reversibility, gdpr_art22: !!impact.gdpr_art22, deployment_scale: impact.deployment_scale,
      },
      data: {
        description: data.description.trim(), sources: splitCsv(data.sources),
        data_classification_code: data.data_classification_code, pii_presence: data.pii_presence,
        sensitive_categories: splitCsv(data.sensitive_categories),
        lawful_basis: data.lawful_basis || null, residency: data.residency || null,
        retention: data.retention || null, use: data.use || null,
      },
      security_access: null, rationale: null,
    }
    try {
      const v = await api.put<AssessmentView>(`/api/intakes/${intakeId}/assessment`, payload)
      setComputed(v.computed); setRevision(v.revision); onComputed()
    } catch (err) {
      setError(err instanceof ApiException ? err.body.detail : 'Could not save the assessment.')
    } finally {
      setBusy(false)
    }
  }

  if (section === null) return null

  const sel = (id: string, label: string, value: string, set: (v: string) => void, opts: Opt[], required = true) => (
    <div className="field">
      <div className="form-field">
        <label className={`form-label${required ? ' is-required' : ''}`} htmlFor={id}>{label}</label>
        <select className={`input${attempted && required && !value ? ' input--error' : ''}`} id={id} value={value} disabled={!canEdit} onChange={(e) => set(e.target.value)}>
          <option value="">Select…</option>
          {opts.map((o) => <option key={o.value} value={o.value}>{o.label}</option>)}
        </select>
        {attempted && required && !value && <span className="input-error-text">Required.</span>}
      </div>
    </div>
  )

  return (
    <form className="aw-tabpanel card" onSubmit={save} noValidate>
      {section === 'impact' ? (
        <>
          <div className="rail-panel__title">AI decision impact</div>
          <div className="field-grid">
            {sel('a-role', 'Decision role', impact.decision_role, (v) => setImpact({ ...impact, decision_role: v }), ROLE)}
            {sel('a-domain', 'Decision domain', impact.decision_domain, (v) => setImpact({ ...impact, decision_domain: v }), DOMAIN)}
            {sel('a-pop', 'Affected population', impact.affected_population, (v) => setImpact({ ...impact, affected_population: v }), POPULATION)}
            {sel('a-impact', 'Worst-case adverse impact', impact.adverse_impact, (v) => setImpact({ ...impact, adverse_impact: v }), IMPACT)}
            {sel('a-oversight', 'Human oversight', impact.oversight_strategy, (v) => setImpact({ ...impact, oversight_strategy: v }), OVERSIGHT)}
            <div className="field">
              <div className="form-field">
                <label className="form-label" htmlFor="a-threshold">Oversight threshold</label>
                <input className="input" id="a-threshold" placeholder="e.g. review all denials" value={impact.oversight_threshold} disabled={!canEdit} onChange={(e) => setImpact({ ...impact, oversight_threshold: e.target.value })} />
                <span className="input-hint">When a human reviews. Optional.</span>
              </div>
            </div>
            {sel('a-rev', 'Reversibility', impact.reversibility, (v) => setImpact({ ...impact, reversibility: v }), REVERSIBILITY)}
            {sel('a-scale', 'Deployment scale', impact.deployment_scale, (v) => setImpact({ ...impact, deployment_scale: v }), SCALE)}
            <div className="field">
              <div className="form-field">
                <label className="form-label is-required">GDPR Art. 22 (solely automated)</label>
                <div className="chip-group" role="radiogroup" aria-label="GDPR Article 22">
                  <button type="button" role="radio" aria-checked={impact.gdpr_art22 === true} className={`chip${impact.gdpr_art22 === true ? ' is-selected' : ''}`} disabled={!canEdit} onClick={() => setImpact({ ...impact, gdpr_art22: true })}>Yes</button>
                  <button type="button" role="radio" aria-checked={impact.gdpr_art22 === false} className={`chip${impact.gdpr_art22 === false ? ' is-selected' : ''}`} disabled={!canEdit} onClick={() => setImpact({ ...impact, gdpr_art22: false })}>No</button>
                </div>
                {attempted && impact.gdpr_art22 === null && <span className="input-error-text">Required.</span>}
              </div>
            </div>
          </div>
        </>
      ) : (
        <>
          <div className="rail-panel__title">Data</div>
          <div className="field-grid">
            <div className="field field-full">
              <div className="form-field">
                <label className="form-label is-required" htmlFor="d-desc">Data description</label>
                <textarea className={`input${attempted && !data.description.trim() ? ' input--error' : ''}`} id="d-desc" placeholder="What data the use case reads / produces." value={data.description} disabled={!canEdit} onChange={(e) => setData({ ...data, description: e.target.value })} />
                {attempted && !data.description.trim() && <span className="input-error-text">Required.</span>}
              </div>
            </div>
            {sel('d-class', 'Data classification', data.data_classification_code, (v) => setData({ ...data, data_classification_code: v }), classifications.map((c) => ({ value: c.code, label: c.label })))}
            {sel('d-pii', 'PII presence', data.pii_presence, (v) => setData({ ...data, pii_presence: v }), PII)}
            <div className="field field-full">
              <div className="form-field">
                <label className="form-label" htmlFor="d-sources">Data sources</label>
                <input className="input" id="d-sources" placeholder="Comma-separated, e.g. policy system, claims DB" value={data.sources} disabled={!canEdit} onChange={(e) => setData({ ...data, sources: e.target.value })} />
              </div>
            </div>
            <div className="field field-full">
              <div className="form-field">
                <label className="form-label" htmlFor="d-sens">Sensitive categories</label>
                <input className="input" id="d-sens" placeholder="Comma-separated, e.g. health, biometric" value={data.sensitive_categories} disabled={!canEdit} onChange={(e) => setData({ ...data, sensitive_categories: e.target.value })} />
                <span className="input-hint">Special-category data, if any. Optional.</span>
              </div>
            </div>
          </div>
        </>
      )}

      {/* shared footer — Save (full snapshot) + computed result, on both sections */}
      {error && <p className="input-error-text">{error}</p>}
      {canEdit && (
        <div className="l-cluster">
          <button type="submit" className="btn btn--primary btn--md" disabled={busy || !valid}>{busy ? 'Saving…' : revision ? 'Save assessment' : 'Compute risk tier'}</button>
          {!valid && <span className="input-hint">Complete both the AI decision impact and Data tabs to compute the tier.</span>}
        </div>
      )}

      {computed && (
        <div className="rail-actions">
          <div className="rail-panel__title">Computed classification{revision ? ` · revision ${revision}` : ''}</div>
          {computed.auto_rejected && (
            <p className="input-error-text"><b>Auto-rejected.</b> An unacceptable risk tier stops this use case — it cannot proceed to approval.</p>
          )}
          <div className="kv">
            <span className="kv__k">Risk tier</span><span className="kv__v">{computed.ai_risk_tier_code ? <Badge table="ai_risk_tier" code={computed.ai_risk_tier_code} /> : '—'}</span>
            {computed.naic_materiality_code && (<><span className="kv__k">NAIC materiality</span><span className="kv__v">{computed.naic_materiality_code}</span></>)}
            {computed.data_classification_code && (<><span className="kv__k">Data classification</span><span className="kv__v">{computed.data_classification_code}</span></>)}
          </div>
        </div>
      )}
    </form>
  )
}
