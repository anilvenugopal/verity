import { type KeyboardEvent, useEffect, useMemo, useState } from 'react'
import { useNavigate } from 'react-router-dom'
import { api } from '@/api/client'
import { fmtTs } from '@/api/format'
import type { Executable } from '@/api/types'
import { useRegistryScope } from '../RegistryContext'
import '../RegistryLists.css'

export function TaskList() {
  const navigate = useNavigate()
  const { appId, appName } = useRegistryScope()
  const [tasks, setTasks] = useState<Executable[] | null>(null)
  const [query, setQuery] = useState('')

  useEffect(() => {
    const url = appId
      ? `/api/executables?kind=task&application_id=${appId}`
      : '/api/executables?kind=task'
    api.get<Executable[]>(url).then(setTasks).catch(() => setTasks([]))
  }, [appId])

  const all = tasks ?? []
  const shown = useMemo(() => {
    const q = query.trim().toLowerCase()
    return q ? all.filter((t) =>
      `${t.display_name ?? ''} ${t.name} ${t.description ?? ''}`.toLowerCase().includes(q)
    ) : all
  }, [all, query])

  const open = (t: Executable) =>
    navigate(t.champion_version_id
      ? `/registry/tasks/${t.executable_id}/versions/${t.champion_version_id}`
      : `/registry/tasks/${t.executable_id}`)
  const onKey = (t: Executable) => (e: KeyboardEvent) => (e.key === 'Enter' || e.key === ' ') && open(t)

  return (
    <div className="canvas-pad">
      <div className="page-head">
        <div>
          <div className="page-head__title">Tasks</div>
          <div className="page-head__sub">
            {appId && appName
              ? <>Showing <strong>{all.length}</strong> task{all.length !== 1 ? 's' : ''} in <strong>{appName}</strong>.</>
              : 'Task executables registered in the governed catalog.'}
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
              placeholder="Search tasks…"
              aria-label="Search tasks"
              value={query}
              onChange={(e) => setQuery(e.target.value)}
            />
          </span>
        </div>

        {tasks === null ? (
          <div className="log-table">
            <div className="empty-state"><div className="empty-state__body">Loading…</div></div>
          </div>
        ) : shown.length === 0 ? (
          <div className="log-table">
            <div className="empty-state">
              <span className="empty-state__icon">
                <svg className="icon" aria-hidden="true"><use href="#i-entity-task" /></svg>
              </span>
              <div className="empty-state__title">{all.length === 0 ? 'No tasks registered' : 'No matches'}</div>
              <p className="empty-state__body">
                {all.length === 0 ? 'Register a task executable to appear here.' : 'No tasks match your search.'}
              </p>
            </div>
          </div>
        ) : (
          <div className="log-table">
            <div className="log-table__header exe-grid">
              <span className="eyebrow">Task</span>
              <span className="eyebrow">Champion</span>
              <span className="eyebrow">Tier</span>
              <span className="eyebrow">Capability</span>
              <span className="eyebrow">Ver</span>
              <span className="eyebrow">Updated</span>
            </div>
            {shown.map((t) => (
              <div
                key={t.executable_id}
                className="log-row exe-grid"
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
                <span>
                  {t.champion_semver
                    ? <span className="chip chip--static">{t.champion_semver}</span>
                    : <span className="reg-count">—</span>}
                </span>
                <span className="reg-entity-desc">{t.champion_governance_tier_code ?? '—'}</span>
                <span className="reg-entity-desc">{t.champion_capability_type_code ?? '—'}</span>
                <span className="reg-count">{t.version_count}</span>
                <span className="reg-entity-desc">{fmtTs(t.updated_at)}</span>
              </div>
            ))}
          </div>
        )}
      </section>
    </div>
  )
}
