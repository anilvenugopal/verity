import { type KeyboardEvent, useEffect, useMemo, useState } from 'react'
import { useNavigate } from 'react-router-dom'
import { api } from '@/api/client'
import { useSession } from '@/auth/useSession'
import type { Application } from '@/api/types'
import { ReviewBadge } from '@/components/ReviewBadge'
import './ApplicationsList.css'

// Registry (FR-014): GET /applications, real-time client-side search, Onboard CTA gated on
// onboard_application; rows → application detail. (FR-015 non-stakeholder read-only modal deferred —
// needs stakeholder data; /me app_team_roles is currently empty.)
export function ApplicationsList() {
  const navigate = useNavigate()
  const { canDo } = useSession()
  const [apps, setApps] = useState<Application[] | null>(null)
  const [query, setQuery] = useState('')

  useEffect(() => {
    api.get<Application[]>('/api/applications').then(setApps).catch(() => setApps([]))
  }, [])

  const shown = useMemo(() => {
    const q = query.trim().toLowerCase()
    return (apps ?? []).filter((a) => `${a.name} ${a.code}`.toLowerCase().includes(q))
  }, [apps, query])

  const open = (id: string) => navigate(`/applications/${id}`)
  const onRowKey = (id: string) => (e: KeyboardEvent) => (e.key === 'Enter' || e.key === ' ') && open(id)

  return (
    <div className="canvas-pad">
      <div className="page-head">
        <div>
          <div className="page-head__title">Applications</div>
          <div className="page-head__sub">Business applications you can access. Each owns its use cases, team, quota and reporting.</div>
        </div>
        {canDo('onboard_application') && (
          <button className="btn btn--primary btn--md" onClick={() => navigate('/applications/new')}>
            <svg className="icon icon--sm" aria-hidden="true"><use href="#i-add" /></svg>
            Onboard application
          </button>
        )}
      </div>

      <section className="section">
        <div className="section__head">
          <span className="eyebrow">Registry</span>
          <span className="l-spacer" />
          <span className="search-field">
            <svg className="icon" aria-hidden="true"><use href="#i-search" /></svg>
            <input size={26} placeholder="Search applications…" aria-label="Search applications" value={query} onChange={(e) => setQuery(e.target.value)} />
          </span>
        </div>

        {apps === null ? (
          <div className="card"><div className="empty-state"><div className="empty-state__body">Loading…</div></div></div>
        ) : shown.length === 0 ? (
          <div className="card">
            <div className="empty-state">
              <span className="empty-state__icon"><svg className="icon" aria-hidden="true"><use href="#i-entity-application" /></svg></span>
              <div className="empty-state__title">{apps.length === 0 ? 'No applications yet' : 'No matches'}</div>
              <p className="empty-state__body">
                {apps.length === 0
                  ? 'Onboard your first application to start governing AI use cases.'
                  : 'No applications match your search.'}
              </p>
              {apps.length === 0 && canDo('onboard_application') && (
                <div className="empty-state__actions">
                  <button className="btn btn--primary btn--md" onClick={() => navigate('/applications/new')}>
                    <svg className="icon icon--sm" aria-hidden="true"><use href="#i-add" /></svg>Onboard application
                  </button>
                </div>
              )}
            </div>
          </div>
        ) : (
          <div className="log-table">
            <div className="log-table__header reg-grid">
              <span className="eyebrow">TLA</span>
              <span className="eyebrow">Application</span>
              <span className="eyebrow">Owner</span>
              <span className="eyebrow">Line of business</span>
              <span className="eyebrow">Status</span>
              <span className="eyebrow">Use cases</span>
            </div>
            {shown.map((a) => (
              <div
                key={a.application_id}
                className="log-row reg-grid"
                role="button"
                tabIndex={0}
                onClick={() => open(a.application_id)}
                onKeyDown={onRowKey(a.application_id)}
              >
                <span className="tla">{a.code}</span>
                <span className="reg-name">{a.name}</span>
                <span className="reg-sub">{a.business_owner_name ?? '—'}</span>
                <span className="reg-sub">{a.line_of_business_code ?? '—'}</span>
                <ReviewBadge app={a} quiet />
                <span className="reg-sub">—</span>
              </div>
            ))}
          </div>
        )}
      </section>
    </div>
  )
}
