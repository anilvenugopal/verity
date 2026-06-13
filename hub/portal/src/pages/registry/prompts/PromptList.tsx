import { type KeyboardEvent, useEffect, useMemo, useState } from 'react'
import { useNavigate } from 'react-router-dom'
import { api } from '@/api/client'
import { fmtTs } from '@/api/format'
import type { PromptSummary } from '@/api/types'
import { useRegistryScope } from '../RegistryContext'
import '../RegistryLists.css'

export function PromptList() {
  const navigate = useNavigate()
  const { appId, appName } = useRegistryScope()
  const [prompts, setPrompts] = useState<PromptSummary[] | null>(null)
  const [query, setQuery] = useState('')

  useEffect(() => {
    const url = appId ? `/api/prompts?application_id=${appId}` : '/api/prompts'
    api.get<PromptSummary[]>(url).then(setPrompts).catch(() => setPrompts([]))
  }, [appId])

  const all = prompts ?? []
  const shown = useMemo(() => {
    const q = query.trim().toLowerCase()
    return q ? all.filter((p) =>
      `${p.display_name ?? ''} ${p.name} ${p.description ?? ''}`.toLowerCase().includes(q)
    ) : all
  }, [all, query])

  const open = (p: PromptSummary) =>
    navigate(p.latest_version_id
      ? `/registry/prompts/${p.prompt_id}/versions/${p.latest_version_id}`
      : `/registry/prompts/${p.prompt_id}`)
  const onKey = (p: PromptSummary) => (e: KeyboardEvent) => (e.key === 'Enter' || e.key === ' ') && open(p)

  return (
    <div className="canvas-pad">
      <div className="page-head">
        <div>
          <div className="page-head__title">Prompts</div>
          <div className="page-head__sub">
            {appId && appName
              ? <>Showing <strong>{all.length}</strong> prompt{all.length !== 1 ? 's' : ''} in <strong>{appName}</strong>.</>
              : 'Versioned prompt templates assigned to agent and task executables.'}
          </div>
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
              placeholder="Search prompts…"
              aria-label="Search prompts"
              value={query}
              onChange={(e) => setQuery(e.target.value)}
            />
          </span>
        </div>

        {prompts === null ? (
          <div className="log-table">
            <div className="empty-state"><div className="empty-state__body">Loading…</div></div>
          </div>
        ) : shown.length === 0 ? (
          <div className="log-table">
            <div className="empty-state">
              <span className="empty-state__icon">
                <svg className="icon" aria-hidden="true"><use href="#i-entity-prompt" /></svg>
              </span>
              <div className="empty-state__title">{all.length === 0 ? 'No prompts registered' : 'No matches'}</div>
              <p className="empty-state__body">
                {all.length === 0 ? 'Register a prompt to appear here.' : 'No prompts match your search.'}
              </p>
            </div>
          </div>
        ) : (
          <div className="log-table">
            <div className="log-table__header prompt-grid">
              <span className="eyebrow">Prompt</span>
              <span className="eyebrow">Versions</span>
              <span className="eyebrow">Updated</span>
            </div>
            {shown.map((p) => (
              <div
                key={p.prompt_id}
                className="log-row prompt-grid"
                role="button"
                tabIndex={0}
                onClick={() => open(p)}
                onKeyDown={onKey(p)}
              >
                <div className="reg-entity-cell">
                  <span className="reg-entity-name">
                    {p.display_name ?? p.name}{' '}
                    <span className="chip chip--code chip--xs">{p.name}</span>
                    {p.application_code && <span className="chip chip--app chip--xs">{p.application_code}</span>}
                  </span>
                  {p.description && <span className="reg-entity-desc">{p.description}</span>}
                </div>
                <span className="reg-count">{p.version_count}</span>
                <span className="reg-entity-desc">{fmtTs(p.updated_at)}</span>
              </div>
            ))}
          </div>
        )}
      </section>
    </div>
  )
}
