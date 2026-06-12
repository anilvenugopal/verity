import { type FormEvent, useEffect, useState } from 'react'
import { Link, useParams } from 'react-router-dom'
import { api, ApiException } from '@/api/client'
import { useSession } from '@/auth/useSession'
import { useToast } from '@/shell/useToast'
import type { ModelReferenceSummary, ModelSummary, UsedByEntry } from '@/api/types'
import '../RegistryDetail.css'
import '../RegistryLists.css'

interface ModelPrice {
  model_price_id: string
  input_price_per_1k: number
  output_price_per_1k: number
  currency_code: string
  valid_from: string
  valid_to: string
}

const fmtPer1M = (per1k: number) => `$${(per1k * 1000).toFixed(2)}`

export function ModelDetail() {
  const { id } = useParams<{ id: string }>()
  const { canDo } = useSession()
  const { success, error } = useToast()
  const canAuthor = canDo('author_registry')

  const [model, setModel] = useState<ModelSummary | null>(null)
  const [prices, setPrices] = useState<ModelPrice[]>([])
  const [references, setReferences] = useState<ModelReferenceSummary[]>([])
  const [usedBy, setUsedBy] = useState<UsedByEntry[] | null>(null)
  const [showRebindFor, setShowRebindFor] = useState<string | null>(null)
  const [newModelId, setNewModelId] = useState('')
  const [rebinding, setRebinding] = useState(false)

  const loadModel = () => {
    if (!id) return
    api.get<ModelSummary>(`/api/models/${id}`).then(setModel).catch(() => setModel(null))
    api.get<ModelPrice[]>(`/api/models/${id}/prices`).then(setPrices).catch(() => setPrices([]))
    api.get<UsedByEntry[]>(`/api/models/${id}/executables`).then(setUsedBy).catch(() => setUsedBy([]))
  }

  useEffect(() => {
    loadModel()
    api.get<ModelReferenceSummary[]>('/api/model-references').then(setReferences).catch(() => setReferences([]))
  }, [id])

  async function handleRebind(refId: string, e: FormEvent) {
    e.preventDefault()
    if (rebinding || !id) return
    setRebinding(true)
    try {
      await api.post(`/api/model-references/${refId}/bindings`, { model_id: id, reason: 'rebind from portal' })
      success('Model reference rebound')
      setShowRebindFor(null)
      setNewModelId('')
      loadModel()
      api.get<ModelReferenceSummary[]>('/api/model-references').then(setReferences).catch(() => {})
    } catch (err) {
      error(err instanceof ApiException ? err.body.detail : 'Rebind failed')
    } finally {
      setRebinding(false)
    }
  }

  if (!id) return null
  if (model === null) return <div className="canvas-pad"><span className="input-hint">Loading…</span></div>

  const boundRefs = references.filter((r) => r.current_model_code === model.model_code)
  const fmtCtx = (n: number | null | undefined) => n != null ? `${Math.round(n / 1000).toLocaleString()}k tokens` : '—'

  return (
    <div className="canvas-pad">
      <div className="page-head">
        <div>
          <div className="page-head__eyebrow"><Link to="/registry/models">Models</Link></div>
          <div className="page-head__title">{model.model_code}</div>
          <div className="page-head__badges">
            <span className="chip chip--static">{model.provider}</span>
            <span className="chip chip--static">{model.modality}</span>
            <span className={`badge badge--${model.model_status_code === 'active' ? 'champion' : 'deprecated'}`}>
              <span className="badge__dot" /><span className="badge__label">{model.model_status_code}</span>
            </span>
          </div>
        </div>
      </div>

      {/* Metadata */}
      <section className="section">
        <div className="section__head"><span className="eyebrow">Metadata</span></div>
        <div className="kv">
          <span className="kv__k">Provider</span>
          <span className="kv__v">{model.provider}</span>
          <span className="kv__k">Modality</span>
          <span className="kv__v">{model.modality}</span>
          <span className="kv__k">Context window</span>
          <span className="kv__v">{fmtCtx(model.context_window)}</span>
          {model.current_price && (
            <>
              <span className="kv__k">Current price</span>
              <span className="kv__v">
                {fmtPer1M(model.current_price.input_price_per_1k)} in / {fmtPer1M(model.current_price.output_price_per_1k)} out per 1M tokens ({model.current_price.currency_code.toUpperCase()})
              </span>
            </>
          )}
        </div>
      </section>

      {/* Price history */}
      <section className="section">
        <div className="section__head"><span className="eyebrow">Price history</span></div>
        <div className="log-table">
          {prices.length === 0 ? (
            <div className="empty-state"><div className="empty-state__body">No pricing data.</div></div>
          ) : (
            <>
              <div className="log-table__header price-grid">
                <span className="eyebrow">In / 1M</span>
                <span className="eyebrow">Out / 1M</span>
                <span className="eyebrow">Currency</span>
                <span className="eyebrow">From</span>
                <span className="eyebrow">To</span>
              </div>
              {prices.map((p) => (
                <div key={p.model_price_id} className="log-row price-grid">
                  <span className="reg-row-primary">{fmtPer1M(p.input_price_per_1k)}</span>
                  <span className="reg-row-primary">{fmtPer1M(p.output_price_per_1k)}</span>
                  <span className="reg-entity-desc">{p.currency_code.toUpperCase()}</span>
                  <span className="reg-entity-desc">{p.valid_from.slice(0, 10)}</span>
                  <span className="reg-entity-desc">{p.valid_to.startsWith('2099') ? 'current' : p.valid_to.slice(0, 10)}</span>
                </div>
              ))}
            </>
          )}
        </div>
      </section>

      {/* Bound references */}
      <section className="section">
        <div className="section__head"><span className="eyebrow">Bound references</span></div>
        <div className="log-table">
          {boundRefs.length === 0 ? (
            <div className="empty-state"><div className="empty-state__body">No model references currently bound to this model.</div></div>
          ) : (
            <>
              <div className="log-table__header model-binding-grid">
                <span className="eyebrow">Reference code</span>
                <span className="eyebrow">Name</span>
                {canAuthor && <span />}
              </div>
              {boundRefs.map((r) => (
                <div key={r.model_reference_id}>
                  <div className="log-row model-binding-grid">
                    <span className="chip chip--static">{r.reference_code}</span>
                    <span className="reg-row-primary">{r.name}</span>
                    {canAuthor && (
                      <button
                        className="btn btn--ghost btn--sm"
                        onClick={() => setShowRebindFor(showRebindFor === r.model_reference_id ? null : r.model_reference_id)}
                      >
                        Rebind
                      </button>
                    )}
                  </div>
                  {showRebindFor === r.model_reference_id && (
                    <div style={{ padding: 'var(--space-2) var(--space-4)', borderTop: '1px solid var(--border-default)', background: 'var(--surface-panel)' }}>
                      <form className="l-cluster" onSubmit={(e) => handleRebind(r.model_reference_id, e)}>
                        <input
                          className="input"
                          placeholder="New model ID (UUID)"
                          value={newModelId}
                          onChange={(e) => setNewModelId(e.target.value)}
                          required
                        />
                        <button className="btn btn--secondary btn--sm" disabled={rebinding || !newModelId}>
                          Confirm rebind
                        </button>
                      </form>
                    </div>
                  )}
                </div>
              ))}
            </>
          )}
        </div>
      </section>

      {/* Used by — which champion agent/task versions use this model */}
      <section className="section">
        <div className="section__head"><span className="eyebrow">Used by</span></div>
        <div className="log-table">
          {usedBy === null ? (
            <div className="empty-state"><div className="empty-state__body">Loading…</div></div>
          ) : usedBy.length === 0 ? (
            <div className="empty-state"><div className="empty-state__body">No champion executable versions currently resolve to this model via their inference config.</div></div>
          ) : (
            <>
              <div className="log-table__header used-by-grid">
                <span className="eyebrow">Executable</span>
                <span className="eyebrow">Kind</span>
                <span className="eyebrow">Version</span>
              </div>
              {usedBy.map((u) => (
                <div key={u.executable_version_id} className="log-row used-by-grid">
                  <Link to={`/registry/${u.kind_code === 'agent' ? 'agents' : 'tasks'}/${u.executable_id}`}
                        className="reg-row-primary">
                    {u.executable_name}
                  </Link>
                  <span className="chip chip--static">{u.kind_code}</span>
                  <span className="reg-entity-desc">{u.semver}</span>
                </div>
              ))}
            </>
          )}
        </div>
      </section>
    </div>
  )
}
