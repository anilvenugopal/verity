import { type KeyboardEvent, useEffect, useMemo, useState } from 'react'
import { useNavigate } from 'react-router-dom'
import { api } from '@/api/client'
import type { ModelSummary } from '@/api/types'
import '../RegistryLists.css'

export function ModelList() {
  const navigate = useNavigate()
  const [models, setModels] = useState<ModelSummary[] | null>(null)
  const [query, setQuery] = useState('')

  useEffect(() => {
    api.get<ModelSummary[]>('/api/models').then(setModels).catch(() => setModels([]))
  }, [])

  const all = models ?? []
  const shown = useMemo(() => {
    const q = query.trim().toLowerCase()
    return q ? all.filter((m) => `${m.model_code} ${m.provider}`.toLowerCase().includes(q)) : all
  }, [all, query])

  const open = (id: string) => navigate(`/registry/models/${id}`)
  const onKey = (id: string) => (e: KeyboardEvent) => (e.key === 'Enter' || e.key === ' ') && open(id)

  const fmtPer1M = (per1k: number) => `$${(per1k * 1000).toFixed(2)}`
  const fmtCtx = (n: number | null | undefined) => n != null ? `${Math.round(n / 1000)}k` : '—'
  const statusVariant = (code: string) => code === 'active' ? 'champion' : 'deprecated'

  return (
    <div className="canvas-pad">
      <div className="page-head">
        <div>
          <div className="page-head__title">Models</div>
          <div className="page-head__sub">LLM catalog with SCD-2 pricing history. Global — not scoped by application.</div>
        </div>
      </div>

      <section className="section">
        <div className="section__head">
          <span className="eyebrow">Catalog</span>
          <span className="l-spacer" />
          <span className="search-field">
            <svg className="icon" aria-hidden="true"><use href="#i-search" /></svg>
            <input
              size={26}
              placeholder="Search models…"
              aria-label="Search models"
              value={query}
              onChange={(e) => setQuery(e.target.value)}
            />
          </span>
        </div>

        {models === null ? (
          <div className="log-table">
            <div className="empty-state"><div className="empty-state__body">Loading…</div></div>
          </div>
        ) : shown.length === 0 ? (
          <div className="log-table">
            <div className="empty-state">
              <span className="empty-state__icon">
                <svg className="icon" aria-hidden="true"><use href="#i-lib-inference" /></svg>
              </span>
              <div className="empty-state__title">{all.length === 0 ? 'No models in catalog' : 'No matches'}</div>
              <p className="empty-state__body">
                {all.length === 0 ? 'Add models to the catalog via the seed or API.' : 'No models match your search.'}
              </p>
            </div>
          </div>
        ) : (
          <div className="log-table">
            <div className="log-table__header model-grid">
              <span className="eyebrow">Model</span>
              <span className="eyebrow">Status</span>
              <span className="eyebrow">In / 1M</span>
              <span className="eyebrow">Out / 1M</span>
              <span className="eyebrow">Context</span>
            </div>
            {shown.map((m) => (
              <div
                key={m.model_id}
                className="log-row model-grid"
                role="button"
                tabIndex={0}
                onClick={() => open(m.model_id)}
                onKeyDown={onKey(m.model_id)}
              >
                <div className="reg-entity-cell">
                  <span className="reg-entity-name">{m.model_code}</span>
                  <span className="reg-entity-desc">{m.provider} · {m.modality}</span>
                </div>
                <span className={`badge badge--${statusVariant(m.model_status_code)}`}>
                  <span className="badge__dot" />
                  <span className="badge__label">{m.model_status_code}</span>
                </span>
                <span className="reg-count">{m.current_price ? fmtPer1M(m.current_price.input_price_per_1k) : '—'}</span>
                <span className="reg-count">{m.current_price ? fmtPer1M(m.current_price.output_price_per_1k) : '—'}</span>
                <span className="reg-count">{fmtCtx(m.context_window)}</span>
              </div>
            ))}
          </div>
        )}
      </section>
    </div>
  )
}
