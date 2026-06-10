import { type KeyboardEvent, useEffect, useMemo, useState } from 'react'
import { useNavigate } from 'react-router-dom'
import { api } from '@/api/client'
import { useSession } from '@/auth/useSession'
import type { IntakeListItem } from '@/api/types'
import { Badge } from '@/components/Badge'
import './UseCasesList.css'

// Top-level Use Cases registry: every intake the user can see, across applications (GET /intakes).
// New use cases are created under an application, so the CTA routes to the app-picker (/intakes/new).
export function UseCasesList() {
  const navigate = useNavigate()
  const { canDo } = useSession()
  const [intakes, setIntakes] = useState<IntakeListItem[] | null>(null)
  const [query, setQuery] = useState('')

  useEffect(() => {
    api.get<IntakeListItem[]>('/api/intakes').then(setIntakes).catch(() => setIntakes([]))
  }, [])

  const shown = useMemo(() => {
    const q = query.trim().toLowerCase()
    return (intakes ?? []).filter((i) => `${i.title} ${i.application_name}`.toLowerCase().includes(q))
  }, [intakes, query])

  const open = (id: string) => navigate(`/intakes/${id}`)
  const onRowKey = (id: string) => (e: KeyboardEvent) => (e.key === 'Enter' || e.key === ' ') && open(id)

  return (
    <div className="canvas-pad">
      <div className="page-head">
        <div>
          <div className="page-head__title">Use cases</div>
          <div className="page-head__sub">AI use cases governed under your applications. Each is assessed, then submitted for tier-based approval.</div>
        </div>
        {canDo('create_intake') && (
          <button className="btn btn--primary btn--md" onClick={() => navigate('/intakes/new')}>
            <svg className="icon icon--sm" aria-hidden="true"><use href="#i-add" /></svg>New use case
          </button>
        )}
      </div>

      <section className="section">
        <div className="section__head">
          <span className="eyebrow">Registry</span>
          <span className="l-spacer" />
          <span className="search-field">
            <svg className="icon" aria-hidden="true"><use href="#i-search" /></svg>
            <input size={26} placeholder="Search use cases…" aria-label="Search use cases" value={query} onChange={(e) => setQuery(e.target.value)} />
          </span>
        </div>

        {intakes === null ? (
          <div className="card"><div className="empty-state"><div className="empty-state__body">Loading…</div></div></div>
        ) : shown.length === 0 ? (
          <div className="card">
            <div className="empty-state">
              <span className="empty-state__icon"><svg className="icon" aria-hidden="true"><use href="#i-entity-task" /></svg></span>
              <div className="empty-state__title">{intakes.length === 0 ? 'No use cases yet' : 'No matches'}</div>
              <p className="empty-state__body">
                {intakes.length === 0 ? 'Create a use case under an active application to start.' : 'No use cases match your search.'}
              </p>
              {intakes.length === 0 && canDo('create_intake') && (
                <div className="empty-state__actions">
                  <button className="btn btn--primary btn--md" onClick={() => navigate('/intakes/new')}>
                    <svg className="icon icon--sm" aria-hidden="true"><use href="#i-add" /></svg>New use case
                  </button>
                </div>
              )}
            </div>
          </div>
        ) : (
          <div className="log-table">
            <div className="log-table__header uc-grid">
              <span className="eyebrow">Use case</span>
              <span className="eyebrow">Application</span>
              <span className="eyebrow">Status</span>
              <span className="eyebrow">Risk tier</span>
            </div>
            {shown.map((i) => (
              <div
                key={i.intake_id}
                className="log-row uc-grid"
                role="button"
                tabIndex={0}
                onClick={() => open(i.intake_id)}
                onKeyDown={onRowKey(i.intake_id)}
              >
                <span className="uc-name">{i.title}</span>
                <span className="uc-sub">{i.application_name}</span>
                <Badge table="intake_status" code={i.intake_status_code} quiet />
                {i.ai_risk_tier_code ? <Badge table="ai_risk_tier" code={i.ai_risk_tier_code} quiet /> : <span className="uc-sub">—</span>}
              </div>
            ))}
          </div>
        )}
      </section>
    </div>
  )
}
