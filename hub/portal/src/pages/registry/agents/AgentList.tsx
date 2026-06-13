import { type KeyboardEvent, useEffect, useMemo, useState } from 'react'
import { useNavigate } from 'react-router-dom'
import { api } from '@/api/client'
import { fmtTs } from '@/api/format'
import type { Executable } from '@/api/types'
import { useRegistryScope } from '../RegistryContext'
import '../RegistryLists.css'

export function AgentList() {
  const navigate = useNavigate()
  const { appId, appName } = useRegistryScope()
  const [agents, setAgents] = useState<Executable[] | null>(null)
  const [query, setQuery] = useState('')

  useEffect(() => {
    const url = appId
      ? `/api/executables?kind=agent&application_id=${appId}`
      : '/api/executables?kind=agent'
    api.get<Executable[]>(url).then(setAgents).catch(() => setAgents([]))
  }, [appId])

  const all = agents ?? []
  const shown = useMemo(() => {
    const q = query.trim().toLowerCase()
    return q ? all.filter((a) =>
      `${a.display_name ?? ''} ${a.name} ${a.description ?? ''}`.toLowerCase().includes(q)
    ) : all
  }, [all, query])

  const open = (a: Executable) =>
    navigate(a.champion_version_id
      ? `/registry/agents/${a.executable_id}/versions/${a.champion_version_id}`
      : `/registry/agents/${a.executable_id}`)
  const onKey = (a: Executable) => (e: KeyboardEvent) => (e.key === 'Enter' || e.key === ' ') && open(a)

  return (
    <div className="canvas-pad">
      <div className="page-head">
        <div>
          <div className="page-head__title">Agents</div>
          <div className="page-head__sub">
            {appId && appName
              ? <>Showing <strong>{all.length}</strong> agent{all.length !== 1 ? 's' : ''} in <strong>{appName}</strong>.</>
              : 'Agent executables registered in the governed catalog.'}
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
              placeholder="Search agents…"
              aria-label="Search agents"
              value={query}
              onChange={(e) => setQuery(e.target.value)}
            />
          </span>
        </div>

        {agents === null ? (
          <div className="log-table">
            <div className="empty-state"><div className="empty-state__body">Loading…</div></div>
          </div>
        ) : shown.length === 0 ? (
          <div className="log-table">
            <div className="empty-state">
              <span className="empty-state__icon">
                <svg className="icon" aria-hidden="true"><use href="#i-entity-agent" /></svg>
              </span>
              <div className="empty-state__title">{all.length === 0 ? 'No agents registered' : 'No matches'}</div>
              <p className="empty-state__body">
                {all.length === 0 ? 'Register an agent executable to appear here.' : 'No agents match your search.'}
              </p>
            </div>
          </div>
        ) : (
          <div className="log-table">
            <div className="log-table__header exe-grid">
              <span className="eyebrow">Agent</span>
              <span className="eyebrow">Champion</span>
              <span className="eyebrow">Tier</span>
              <span className="eyebrow">Capability</span>
              <span className="eyebrow">Ver</span>
              <span className="eyebrow">Updated</span>
            </div>
            {shown.map((a) => (
              <div
                key={a.executable_id}
                className="log-row exe-grid"
                role="button"
                tabIndex={0}
                onClick={() => open(a)}
                onKeyDown={onKey(a)}
              >
                <div className="reg-entity-cell">
                  <span className="reg-entity-name">
                    {a.display_name ?? a.name}{' '}
                    <span className="chip chip--code chip--xs">{a.name}</span>
                    {a.application_code && <span className="chip chip--app chip--xs">{a.application_code}</span>}
                  </span>
                  {a.description && <span className="reg-entity-desc">{a.description}</span>}
                </div>
                <span>
                  {a.champion_semver
                    ? <span className="chip chip--static">{a.champion_semver}</span>
                    : <span className="reg-count">—</span>}
                </span>
                <span className="reg-entity-desc">{a.champion_governance_tier_code ?? '—'}</span>
                <span className="reg-entity-desc">{a.champion_capability_type_code ?? '—'}</span>
                <span className="reg-count">{a.version_count}</span>
                <span className="reg-entity-desc">{fmtTs(a.updated_at)}</span>
              </div>
            ))}
          </div>
        )}
      </section>
    </div>
  )
}
