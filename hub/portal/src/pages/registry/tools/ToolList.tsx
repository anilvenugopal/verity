import { type KeyboardEvent, useEffect, useMemo, useState } from 'react'
import { useNavigate } from 'react-router-dom'
import { api } from '@/api/client'
import type { ToolSummary } from '@/api/types'
import { useRegistryScope } from '../RegistryContext'
import '../RegistryLists.css'

export function ToolList() {
  const navigate = useNavigate()
  const { appId, appName } = useRegistryScope()
  const [tools, setTools] = useState<ToolSummary[] | null>(null)
  const [query, setQuery] = useState('')

  useEffect(() => {
    const url = appId ? `/api/tools?application_id=${appId}` : '/api/tools'
    api.get<ToolSummary[]>(url).then(setTools).catch(() => setTools([]))
  }, [appId])

  const all = tools ?? []
  const shown = useMemo(() => {
    const q = query.trim().toLowerCase()
    return q
      ? all.filter((t) =>
          `${t.display_name ?? ''} ${t.name} ${t.description ?? ''} ${t.transport_code}`.toLowerCase().includes(q)
        )
      : all
  }, [all, query])

  const open = (t: ToolSummary) =>
    navigate(t.latest_version_id
      ? `/registry/tools/${t.tool_id}/versions/${t.latest_version_id}`
      : `/registry/tools/${t.tool_id}`)
  const onKey = (t: ToolSummary) => (e: KeyboardEvent) => (e.key === 'Enter' || e.key === ' ') && open(t)

  return (
    <div className="canvas-pad">
      <div className="page-head">
        <div>
          <div className="page-head__title">Tools</div>
          <div className="page-head__sub">
            {appId && appName
              ? <>Showing <strong>{all.length}</strong> tool{all.length !== 1 ? 's' : ''} in <strong>{appName}</strong>.</>
              : 'Tool components available for assignment to agent executables.'}
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
              placeholder="Search tools…"
              aria-label="Search tools"
              value={query}
              onChange={(e) => setQuery(e.target.value)}
            />
          </span>
        </div>

        {tools === null ? (
          <div className="log-table">
            <div className="empty-state"><div className="empty-state__body">Loading…</div></div>
          </div>
        ) : shown.length === 0 ? (
          <div className="log-table">
            <div className="empty-state">
              <span className="empty-state__icon">
                <svg className="icon" aria-hidden="true"><use href="#i-lib-tools" /></svg>
              </span>
              <div className="empty-state__title">{all.length === 0 ? 'No tools registered' : 'No matches'}</div>
              <p className="empty-state__body">
                {all.length === 0 ? 'Register a tool to appear here.' : 'No tools match your search.'}
              </p>
            </div>
          </div>
        ) : (
          <div className="log-table">
            <div className="log-table__header tool-grid">
              <span className="eyebrow">Tool</span>
              <span className="eyebrow">Transport</span>
              <span className="eyebrow">Write</span>
            </div>
            {shown.map((t) => (
              <div
                key={t.tool_id}
                className="log-row tool-grid"
                role="button"
                tabIndex={0}
                onClick={() => open(t)}
                onKeyDown={onKey(t)}
              >
                <div className="reg-entity-cell">
                  <span className="reg-entity-name">
                    {t.display_name ?? t.name}{' '}
                    <span className="chip chip--code chip--xs">{t.name}</span>
                    {t.application_code && <span className="chip chip--app chip--xs">{t.application_code}</span>}
                  </span>
                  {t.description && <span className="reg-entity-desc">{t.description}</span>}
                </div>
                <span className="chip chip--static">{t.transport_code.replace(/_/g, ' ')}</span>
                <span>
                  {t.is_write_operation
                    ? <span className="chip chip--warn">Write</span>
                    : <span className="reg-count">—</span>}
                </span>
              </div>
            ))}
          </div>
        )}
      </section>
    </div>
  )
}
