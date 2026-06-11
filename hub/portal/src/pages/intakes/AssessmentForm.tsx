import { type FormEvent, useEffect, useState } from 'react'
import { api, ApiException } from '@/api/client'
import { useToast } from '@/shell/useToast'
import type {
  AssessmentInput, AssessmentView, DataItem, FairnessMetric, OversightControl, RiskItem,
} from '@/api/types'
import { Badge } from '@/components/Badge'
import { HelpPopover } from '@/shell/HelpPopover'
import { FieldHelp } from './FieldHelp'
import { InventoryEditor } from './InventoryEditor'
import { FIELDS, type Opt } from './assessmentCatalog'
import './Assessment.css'

// The comprehensive sectioned assessment (FR-026, A+B+C+D). One scrolling form with a sticky section
// nav (status badges), multi-entry data / oversight-control / risk / fairness-metric inventories, and
// the three-layer per-field help. Saves the FULL snapshot in one PUT (FR-027) → backend computes the
// tier + derives the intake-level classification/PII from the data inventory.

type RefCode = { code: string; label: string }

const BLANK: AssessmentInput = {
  decision_context: {
    decision_type: '', consumer_effect: '', annex_iii_high_risk: false, solely_automated: false,
    affected_populations: [], deployment_scale: '',
  },
  data_inventory: [],
  human_oversight: { autonomy_level: '', stop_mechanism: false, controls: [] },
  risks: [],
  fairness: { disparate_impact_tested: false, protected_classes_tested: [], metrics: [], less_discriminatory_alternative: '' },
}

const blankData = (): DataItem => ({ name: '', direction: '', data_type: '', source: '', classification: '', pii_presence: '' })
const blankControl = (): OversightControl => ({ name: '', stage: '', responsible_role: '', trigger: '', can_override: false, what_inspected: '' })
const blankRisk = (): RiskItem => ({ description: '', category: '', likelihood: '', severity: '', mitigation: '', residual: '' })
const blankMetric = (): FairnessMetric => ({ name: '', group: '', value: '' })

const SECTIONS = [
  { key: 'context', label: 'Decision context' },
  { key: 'data', label: 'Data inventory' },
  { key: 'oversight', label: 'Human oversight' },
  { key: 'risks', label: 'Risks' },
  { key: 'fairness', label: 'Fairness' },
]

export function AssessmentForm({
  intakeId, canEdit, onComputed,
}: {
  intakeId: string
  canEdit: boolean
  onComputed: () => void
}) {
  const [d, setD] = useState<AssessmentInput>(BLANK)
  const [computed, setComputed] = useState<AssessmentView['computed']>(null)
  const [revision, setRevision] = useState<number | null>(null)
  const [classes, setClasses] = useState<RefCode[]>([])
  const [active, setActive] = useState('context')
  const { success } = useToast()
  const [busy, setBusy] = useState(false)
  const [attempted, setAttempted] = useState(false)
  const [error, setError] = useState('')

  useEffect(() => {
    api.get<{ data_classifications: RefCode[] }>('/api/reference/onboarding').then((r) => setClasses(r.data_classifications)).catch(() => undefined)
  }, [])

  useEffect(() => {
    api.get<AssessmentView>(`/api/intakes/${intakeId}/assessment`).then((v) => {
      const a = v.assessment as unknown as AssessmentInput
      setD({ ...BLANK, ...a, fairness: { ...BLANK.fairness!, ...(a.fairness ?? {}) } })
      setComputed(v.computed); setRevision(v.revision)
    }).catch(() => undefined) // 404 = not assessed yet
  }, [intakeId])

  // patch helpers
  const dc = d.decision_context, ho = d.human_oversight, fair = d.fairness!
  const setDC = (patch: Partial<typeof dc>) => setD({ ...d, decision_context: { ...dc, ...patch } })
  const setHO = (patch: Partial<typeof ho>) => setD({ ...d, human_oversight: { ...ho, ...patch } })
  const setFair = (patch: Partial<typeof fair>) => setD({ ...d, fairness: { ...fair, ...patch } })

  // validation
  const ctxOk = !!(dc.decision_type && dc.consumer_effect && dc.deployment_scale) && dc.affected_populations.length > 0
  const dataOk = d.data_inventory.length >= 1 && d.data_inventory.every((x) => x.name.trim() && x.direction && x.data_type && x.source && x.classification && x.pii_presence)
  const ovOk = !!ho.autonomy_level && ho.controls.every((c) => c.name.trim() && c.stage && c.responsible_role.trim())
  const risksOk = (d.risks ?? []).every((r) => r.description.trim() && r.category && r.likelihood && r.severity)
  const okByKey: Record<string, boolean> = { context: ctxOk, data: dataOk, oversight: ovOk, risks: risksOk, fairness: true }
  const valid = ctxOk && dataOk && ovOk && risksOk

  async function save(e: FormEvent) {
    e.preventDefault()
    if (busy || !canEdit) return
    if (!valid) { setAttempted(true); return }
    setBusy(true); setError('')
    try {
      const v = await api.put<AssessmentView>(`/api/intakes/${intakeId}/assessment`, d)
      setComputed(v.computed); setRevision(v.revision); onComputed()
      success('Assessment saved')
    } catch (err) {
      setError(err instanceof ApiException ? err.body.detail : 'Could not save the assessment.')
    } finally {
      setBusy(false)
    }
  }

  // ── field building blocks (reused at top level and inside inventory items) ──
  const errCls = (req: boolean, v: unknown) => (attempted && req && !v ? ' input--error' : '')
  const sel = (id: string, key: string, value: string, on: (v: string) => void, opts?: Opt[], req = true) => (
    <div className="field">
      <div className="form-field">
        <FieldHelp field={FIELDS[key] ?? { label: key, help: '' }} required={req} htmlFor={id} />
        <select id={id} className={`input${errCls(req, value)}`} value={value} disabled={!canEdit} onChange={(e) => on(e.target.value)}>
          <option value="">Select…</option>
          {(opts ?? FIELDS[key]?.options ?? []).map((o) => <option key={o.value} value={o.value}>{o.label}</option>)}
        </select>
        {FIELDS[key]?.help && <span className="input-hint">{FIELDS[key].help}</span>}
      </div>
    </div>
  )
  const bool = (key: string, value: boolean, on: (v: boolean) => void) => (
    <div className="field">
      <div className="form-field">
        <FieldHelp field={FIELDS[key] ?? { label: key, help: '' }} />
        <div className="chip-group" role="radiogroup" aria-label={FIELDS[key]?.label ?? key}>
          <button type="button" role="radio" aria-checked={value} className={`chip${value ? ' is-selected' : ''}`} disabled={!canEdit} onClick={() => on(true)}>Yes</button>
          <button type="button" role="radio" aria-checked={!value} className={`chip${!value ? ' is-selected' : ''}`} disabled={!canEdit} onClick={() => on(false)}>No</button>
        </div>
        {FIELDS[key]?.help && <span className="input-hint">{FIELDS[key]?.help}</span>}
      </div>
    </div>
  )
  const txt = (id: string, key: string, value: string, on: (v: string) => void, full = false, req = false) => (
    <div className={`field${full ? ' field-full' : ''}`}>
      <div className="form-field">
        <FieldHelp field={FIELDS[key] ?? { label: key, help: '' }} required={req} htmlFor={id} />
        <input id={id} className={`input${errCls(req, value.trim())}`} value={value} disabled={!canEdit} onChange={(e) => on(e.target.value)} />
        {FIELDS[key]?.help && <span className="input-hint">{FIELDS[key].help}</span>}
      </div>
    </div>
  )
  const plainTxt = (id: string, label: string, value: string, on: (v: string) => void, hint?: string, full = true) => (
    <div className={`field${full ? ' field-full' : ''}`}>
      <div className="form-field">
        <label className="form-label" htmlFor={id}>{label}</label>
        <input id={id} className="input" value={value} disabled={!canEdit} onChange={(e) => on(e.target.value)} />
        {hint && <span className="input-hint">{hint}</span>}
      </div>
    </div>
  )

  const classOpts = classes.map((c) => ({ value: c.code, label: c.label }))

  return (
    <form className="aw-tabpanel card" onSubmit={save} noValidate>
      {!canEdit && <p className="input-hint">Read-only — this assessment can’t be edited{revision ? '' : ' (none captured yet)'}.</p>}

      <div className="asec">
        <nav className="asec__nav" aria-label="Assessment sections">
          {SECTIONS.map((s) => (
            <button
              type="button"
              key={s.key}
              className={`asec__nav-item${active === s.key ? ' is-active' : ''}${okByKey[s.key] ? ' is-done' : attempted ? ' is-error' : ''}`}
              onClick={() => { setActive(s.key); document.getElementById(`asec-${s.key}`)?.scrollIntoView({ behavior: 'smooth', block: 'start' }) }}
            >
              {s.label}
              <span className="asec__nav-item__mark">{okByKey[s.key] ? '✓' : attempted ? '!' : ''}</span>
            </button>
          ))}
        </nav>

        <div className="asec__sections">
          {/* Decision context */}
          <section className="card" id="asec-context">
            <div className="rail-panel__title">Decision context<HelpPopover helpId="forms.assessment.fields.decision_type" /></div>
            <div className="field-grid">
              {sel('a-dtype', 'decision_type', dc.decision_type, (v) => setDC({ decision_type: v }))}
              {sel('a-effect', 'consumer_effect', dc.consumer_effect, (v) => setDC({ consumer_effect: v }))}
              {sel('a-scale', 'deployment_scale', dc.deployment_scale, (v) => setDC({ deployment_scale: v }))}
              {bool('annex_iii_high_risk', dc.annex_iii_high_risk, (v) => setDC({ annex_iii_high_risk: v }))}
              {bool('solely_automated', dc.solely_automated, (v) => setDC({ solely_automated: v }))}
              <div className="field field-full">
                <div className="form-field">
                  <FieldHelp field={FIELDS.affected_populations ?? { label: 'Affected populations', help: '' }} required />
                  <div className="chip-group" aria-label="Affected populations">
                    {(FIELDS.affected_populations?.options ?? []).map((o) => {
                      const on = dc.affected_populations.includes(o.value)
                      return (
                        <button type="button" key={o.value} className={`chip${on ? ' is-selected' : ''}`} disabled={!canEdit}
                                onClick={() => setDC({ affected_populations: on ? dc.affected_populations.filter((x) => x !== o.value) : [...dc.affected_populations, o.value] })}>
                          {o.label}
                        </button>
                      )
                    })}
                  </div>
                  <span className="input-hint">{FIELDS.affected_populations?.help}</span>
                  {attempted && dc.affected_populations.length === 0 && <span className="input-error-text">Select at least one.</span>}
                </div>
              </div>
            </div>
          </section>

          {/* Data inventory */}
          <section className="card" id="asec-data">
            <div className="rail-panel__title">Data inventory<HelpPopover helpId="forms.assessment.fields.source" /></div>
            <p className="input-hint">Every data input the use case consumes and every output it produces (EU AI Act Art 10). The intake’s overall classification + PII are taken from the most sensitive item.</p>
            <InventoryEditor<DataItem>
              items={d.data_inventory} canEdit={canEdit}
              onChange={(next) => setD({ ...d, data_inventory: next })}
              blank={blankData} addLabel="+ Add data asset"
              emptyText="No data assets yet — add at least one input or output."
              label={(it, i) => it.name?.trim() || `Data asset #${i + 1}`}
              render={(it, set) => (
                <>
                  {txt(`di-name`, 'name', it.name, (v) => set({ name: v }), true, true)}
                  {sel('di-dir', 'direction', it.direction, (v) => set({ direction: v }))}
                  {sel('di-type', 'data_type', it.data_type, (v) => set({ data_type: v }))}
                  {sel('di-src', 'source', it.source, (v) => set({ source: v }))}
                  {sel('di-class', 'classification', it.classification, (v) => set({ classification: v }), classOpts)}
                  {sel('di-pii', 'pii_presence', it.pii_presence, (v) => set({ pii_presence: v }))}
                  {plainTxt('di-basis', 'Lawful basis', it.lawful_basis ?? '', (v) => set({ lawful_basis: v }), 'GDPR ground (required when personal data is present).', false)}
                  {plainTxt('di-ret', 'Retention', it.retention ?? '', (v) => set({ retention: v }), 'How long it is kept.', false)}
                </>
              )}
            />
          </section>

          {/* Human oversight */}
          <section className="card" id="asec-oversight">
            <div className="rail-panel__title">Human oversight<HelpPopover helpId="forms.assessment.fields.autonomy_level" /></div>
            <div className="field-grid">
              {sel('a-auto', 'autonomy_level', ho.autonomy_level, (v) => setHO({ autonomy_level: v }))}
              {bool('stop_mechanism', ho.stop_mechanism, (v) => setHO({ stop_mechanism: v }))}
            </div>
            <p className="input-hint">Oversight measures (EU AI Act Art 14) — who oversees the system and how. A control the human can override, or a stop button, lowers the inherent risk tier.</p>
            <InventoryEditor<OversightControl>
              items={ho.controls} canEdit={canEdit}
              onChange={(next) => setHO({ controls: next })}
              blank={blankControl} addLabel="+ Add oversight control"
              emptyText="No oversight controls yet."
              label={(it, i) => it.name?.trim() || `Control #${i + 1}`}
              render={(it, set) => (
                <>
                  {plainTxt('oc-name', 'Control name', it.name, (v) => set({ name: v }), undefined, true)}
                  {sel('oc-stage', 'stage', it.stage, (v) => set({ stage: v }))}
                  {plainTxt('oc-role', 'Responsible role', it.responsible_role, (v) => set({ responsible_role: v }), 'Who performs it.', false)}
                  {plainTxt('oc-trig', 'Trigger', it.trigger ?? '', (v) => set({ trigger: v }), 'When it fires.', false)}
                  {bool('can_override', it.can_override, (v) => set({ can_override: v }))}
                  {plainTxt('oc-insp', 'What is inspected', it.what_inspected ?? '', (v) => set({ what_inspected: v }), undefined, true)}
                </>
              )}
            />
          </section>

          {/* Risks */}
          <section className="card" id="asec-risks">
            <div className="rail-panel__title">Risks<HelpPopover helpId="forms.assessment.fields.category" /></div>
            <p className="input-hint">Risks to health, safety or fundamental rights, scored likelihood × severity (EU AI Act Art 9 / ICO register). Optional, but expected for higher-tier use cases.</p>
            <InventoryEditor<RiskItem>
              items={d.risks ?? []} canEdit={canEdit}
              onChange={(next) => setD({ ...d, risks: next })}
              blank={blankRisk} addLabel="+ Add risk"
              emptyText="No risks recorded yet."
              label={(it, i) => it.description?.trim()?.slice(0, 40) || `Risk #${i + 1}`}
              render={(it, set) => (
                <>
                  {plainTxt('rk-desc', 'Description', it.description, (v) => set({ description: v }), undefined, true)}
                  {sel('rk-cat', 'category', it.category, (v) => set({ category: v }))}
                  {sel('rk-like', 'likelihood', it.likelihood, (v) => set({ likelihood: v }))}
                  {sel('rk-sev', 'severity', it.severity, (v) => set({ severity: v }))}
                  {plainTxt('rk-mit', 'Mitigation', it.mitigation ?? '', (v) => set({ mitigation: v }), undefined, true)}
                  {sel('rk-res', 'residual', it.residual ?? '', (v) => set({ residual: v }), undefined, false)}
                </>
              )}
            />
          </section>

          {/* Fairness */}
          <section className="card" id="asec-fairness">
            <div className="rail-panel__title">Fairness<HelpPopover helpId="forms.assessment.fields.disparate_impact_tested" /></div>
            <div className="field-grid">
              {bool('disparate_impact_tested', fair.disparate_impact_tested, (v) => setFair({ disparate_impact_tested: v }))}
              {plainTxt('fa-classes', 'Protected classes tested', fair.protected_classes_tested.join(', '), (v) => setFair({ protected_classes_tested: v.split(',').map((x) => x.trim()).filter(Boolean) }), 'Comma-separated, e.g. race, gender, age.')}
            </div>
            <p className="input-hint">Quantitative disparate-impact metrics (NY DFS CL-7 / Colorado SB21-169) — e.g. Adverse Impact Ratio per group.</p>
            <InventoryEditor<FairnessMetric>
              items={fair.metrics} canEdit={canEdit}
              onChange={(next) => setFair({ metrics: next })}
              blank={blankMetric} addLabel="+ Add metric"
              emptyText="No fairness metrics recorded yet."
              label={(it, i) => it.name?.trim() || `Metric #${i + 1}`}
              render={(it, set) => (
                <>
                  {plainTxt('fm-name', 'Metric', it.name, (v) => set({ name: v }), 'e.g. Adverse Impact Ratio', false)}
                  {plainTxt('fm-group', 'Group', it.group ?? '', (v) => set({ group: v }), 'Protected group', false)}
                  {plainTxt('fm-val', 'Value', it.value ?? '', (v) => set({ value: v }), undefined, false)}
                </>
              )}
            />
            {plainTxt('fa-lda', 'Less-discriminatory alternative', fair.less_discriminatory_alternative ?? '', (v) => setFair({ less_discriminatory_alternative: v }), 'The search for a less-discriminatory alternative and its result.')}
          </section>
        </div>
      </div>

      {/* Save + computed result */}
      {error && <p className="input-error-text">{error}</p>}
      {canEdit && (
        <div className="l-cluster">
          <button type="submit" className="btn btn--primary btn--md" disabled={busy || !valid}>{busy ? 'Saving…' : revision ? 'Save assessment' : 'Compute risk tier'}</button>
          {!valid && <span className="input-hint">Complete the Decision context, Data inventory and Human oversight sections to compute the tier.</span>}
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
