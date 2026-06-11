import { type FormEvent, Fragment, useCallback, useEffect, useState } from 'react'
import { api } from '@/api/client'
import { useSession } from '@/auth/useSession'
import { useToast } from '@/shell/useToast'
import type { Executable, ExceptionListItem, IntakeAssetLink, ObligationSet } from '@/api/types'
import { domainLabel } from '../compliance/ComplianceModel'

// Risk & Obligations tab (003 US1, FR-007). The intake's obligation set resolved from the metamodel,
// each obligation's derived status, the controls + evidence affordances, and compliance exceptions
// (raise + approve, separation of duty). Reuses canonical classes — no new CSS.
export function RiskObligations({ intakeId, revisable }: { intakeId: string; revisable: boolean }) {
  const { canDo, principal } = useSession()
  const { success } = useToast()
  const [set, setSet] = useState<ObligationSet | null>(null)
  const [excs, setExcs] = useState<ExceptionListItem[]>([])
  const [links, setLinks] = useState<IntakeAssetLink[]>([])
  const [assets, setAssets] = useState<Executable[]>([])
  const [pick, setPick] = useState('')
  const [busy, setBusy] = useState(false)
  const [form, setForm] = useState<{ code: string; tier: number; comp: string; why: string; expires: string } | null>(null)

  const canRecord = revisable && canDo('record_evidence')
  const canExcept = revisable && canDo('edit_impact_assessment')
  const canApprove = canDo('approve_exception')
  const canLink = canDo('link_asset')

  const load = useCallback(() => {
    api.get<ObligationSet>(`/api/intakes/${intakeId}/obligations`).then(setSet).catch(() => setSet(null))
    api.get<ExceptionListItem[]>(`/api/intakes/${intakeId}/exceptions`).then(setExcs).catch(() => setExcs([]))
    api.get<IntakeAssetLink[]>(`/api/intakes/${intakeId}/links`).then(setLinks).catch(() => setLinks([]))
    if (canLink) api.get<Executable[]>('/api/executables').then(setAssets).catch(() => setAssets([]))
  }, [intakeId, canLink])

  async function linkAsset() {
    if (!pick || busy) return
    setBusy(true)
    try { await api.post(`/api/intakes/${intakeId}/links`, { executable_id: pick }); setPick(''); success('Asset linked'); load() } finally { setBusy(false) }
  }
  useEffect(() => load(), [load])

  async function record(obId: string, control: string) {
    if (busy) return
    setBusy(true)
    try { await api.post(`/api/obligations/${obId}/evidence`, { control_code: control }); success('Evidence recorded'); load() } finally { setBusy(false) }
  }
  async function raise(e: FormEvent) {
    e.preventDefault()
    if (!form || busy) return
    setBusy(true)
    try {
      await api.post(`/api/intakes/${intakeId}/exceptions`, {
        requirement_code: form.code, waived_tier_level: form.tier, compensating_controls: form.comp,
        rationale: form.why, expires_at: new Date(form.expires).toISOString(),
      })
      setForm(null); success('Exception raised'); load()
    } finally { setBusy(false) }
  }
  async function signoff(id: string, decision: 'approved' | 'rejected') {
    if (busy) return
    setBusy(true)
    try { await api.post(`/api/exceptions/${id}/signoff`, { decision }); success(decision === 'approved' ? 'Exception approved' : 'Exception rejected'); load() } finally { setBusy(false) }
  }

  if (!set) return <div className="aw-tabpanel card"><p className="input-hint">Loading…</p></div>
  if (set.obligations.length === 0) return <div className="aw-tabpanel card"><p className="input-hint">No obligations resolved yet — complete the assessment (it computes the tier and resolves the applicable obligations from the metamodel).</p></div>

  const domains = [...new Set(set.obligations.map((o) => o.governance_domain_code))]
  return (
    <div className="aw-tabpanel card">
      <div className="rail-panel__title">Risk &amp; obligations</div>
      <div className="l-cluster">
        <span className="chip chip--static">{set.rollup.satisfied} satisfied</span>
        <span className="chip chip--static">{set.rollup.excepted} excepted</span>
        <span className="chip chip--static">{set.rollup.outstanding} outstanding</span>
        {set.rollup.all_resolved && <span className="chip chip--static">✓ all resolved</span>}
      </div>

      {domains.map((d) => (
        <Fragment key={d}>
          <div className="rail-panel__title">{domainLabel(d)}</div>
          <div className="kv">
            {set.obligations.filter((o) => o.governance_domain_code === d).map((o) => (
              <Fragment key={o.intake_obligation_id}>
                <span className="kv__k">{o.requirement_code}<div className="u-text-tertiary">tier {o.target_tier}</div></span>
                <span className="kv__v">
                  <strong>{o.title}</strong> <span className="chip chip--static">{o.status}</span>
                  {o.controls.map((c) => (
                    <div className="l-cluster" key={c.control_code}>
                      <span>{c.evidenced ? '✓' : '○'} {c.title}</span>
                      <span className="chip chip--static">{c.control_phase_code}</span>
                      <span className="chip chip--static">enforce: {c.enforcement_action_code}</span>
                      {!c.evidenced && canRecord && o.status !== 'excepted' && (
                        <button className="btn btn--ghost btn--sm" disabled={busy} onClick={() => record(o.intake_obligation_id, c.control_code)}>Record evidence</button>
                      )}
                    </div>
                  ))}
                  {o.status === 'outstanding' && canExcept && form?.code !== o.requirement_code && (
                    <div className="l-cluster"><button className="btn btn--ghost btn--sm" onClick={() => setForm({ code: o.requirement_code, tier: o.target_tier, comp: '', why: '', expires: '' })}>Raise exception</button></div>
                  )}
                  {form?.code === o.requirement_code && (
                    <form className="field-grid" onSubmit={raise}>
                      <div className="field field-full"><div className="form-field"><label className="form-label is-required">Compensating controls</label>
                        <input className="input" value={form.comp} onChange={(e) => setForm({ ...form, comp: e.target.value })} required /></div></div>
                      <div className="field field-full"><div className="form-field"><label className="form-label is-required">Rationale</label>
                        <input className="input" value={form.why} onChange={(e) => setForm({ ...form, why: e.target.value })} required /></div></div>
                      <div className="field"><div className="form-field"><label className="form-label is-required">Expires</label>
                        <input className="input" type="date" value={form.expires} onChange={(e) => setForm({ ...form, expires: e.target.value })} required /></div></div>
                      <div className="field field-full"><div className="l-cluster">
                        <button type="submit" className="btn btn--secondary btn--sm" disabled={busy || !form.comp || !form.why || !form.expires}>Submit exception</button>
                        <button type="button" className="btn btn--ghost btn--sm" onClick={() => setForm(null)}>Cancel</button>
                      </div></div>
                    </form>
                  )}
                </span>
              </Fragment>
            ))}
          </div>
        </Fragment>
      ))}

      {excs.length > 0 && (
        <>
          <div className="rail-panel__title">Exceptions</div>
          <div className="kv">
            {excs.map((x) => (
              <Fragment key={x.compliance_exception_id}>
                <span className="kv__k">{x.requirement_code}<div className="u-text-tertiary">tier {x.waived_tier_level}</div></span>
                <span className="kv__v">
                  <span className="chip chip--static">{x.exception_status_code}</span> <span className="u-text-tertiary">expires {new Date(x.expires_at).toLocaleDateString()}</span>
                  <div className="u-text-tertiary">{x.rationale}</div>
                  {x.exception_status_code === 'requested' && canApprove && principal?.actor_id !== x.opened_by_actor_id && (
                    <div className="l-cluster">
                      <button className="btn btn--positive btn--sm" disabled={busy} onClick={() => signoff(x.compliance_exception_id, 'approved')}>Approve</button>
                      <button className="btn btn--ghost btn--sm" disabled={busy} onClick={() => signoff(x.compliance_exception_id, 'rejected')}>Reject</button>
                    </div>
                  )}
                  {x.exception_status_code === 'requested' && principal?.actor_id === x.opened_by_actor_id && (
                    <span className="input-hint">Awaiting a compliance/security approver (you raised it — separation of duty).</span>
                  )}
                </span>
              </Fragment>
            ))}
          </div>
        </>
      )}

      {/* Linked assets (003 US2) — the registry assets realizing this intake + their stage; promotion
          to a production stage is gated on this intake being approved + obligations resolved. */}
      <div className="rail-panel__title">Linked assets</div>
      {links.length === 0 ? <p className="input-hint">No assets linked yet.</p> : (
        <div className="kv">
          {links.map((l) => (
            <Fragment key={l.intake_entity_link_id}>
              <span className="kv__k">{l.name}<div className="u-text-tertiary">{l.kind_code}</div></span>
              <span className="kv__v"><span className="chip chip--static">{l.top_stage ?? 'draft'}</span></span>
            </Fragment>
          ))}
        </div>
      )}
      {canLink && (
        <div className="l-cluster">
          <select className="input" value={pick} onChange={(e) => setPick(e.target.value)}>
            <option value="">Link an asset…</option>
            {assets.filter((a) => !links.some((l) => l.executable_id === a.executable_id)).map((a) => <option key={a.executable_id} value={a.executable_id}>{a.name}</option>)}
          </select>
          <button className="btn btn--secondary btn--sm" disabled={busy || !pick} onClick={linkAsset}>Link</button>
        </div>
      )}
    </div>
  )
}
