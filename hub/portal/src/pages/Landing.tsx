import { useEffect, useState } from 'react'
import { api } from '@/api/client'
import { useSession } from '@/auth/useSession'
import { NAV } from '@/shell/nav'
import './Landing.css'

interface Stats {
  applications: number
  pending_approvals: number
  active_decisions: number
}
const ZERO: Stats = { applications: 0, pending_approvals: 0, active_decisions: 0 }

// Home landing (FR-012): welcome + quick-stats (zeros until GET /dashboard/stats exists, US3 T038)
// + jump-back-in cards + a recent-decisions empty state. Rendered into the shell canvas.
export function Landing() {
  const { principal } = useSession()
  const [stats, setStats] = useState<Stats>(ZERO)

  useEffect(() => {
    api.get<Stats>('/api/dashboard/stats').then(setStats).catch(() => setStats(ZERO))
  }, [])

  const jump = NAV.filter((n) => n.key === 'intake' || n.key === 'studio')

  return (
    <div className="canvas-pad">
      <div className="page-head">
        <div className="page-head__title">Welcome back, {principal?.display_name ?? ''}</div>
        <div className="page-head__sub">Governance for regulated AI</div>
      </div>

      <section className="section">
        <div className="section__head"><span className="eyebrow">Overview</span></div>
        <div className="l-grid l-grid--4col">
          <div className="stat"><span className="stat__label">Applications</span><span className="stat__value">{stats.applications}</span></div>
          <div className="stat"><span className="stat__label">Pending approvals</span><span className="stat__value">{stats.pending_approvals}</span></div>
          <div className="stat"><span className="stat__label">Active decisions</span><span className="stat__value">{stats.active_decisions}</span></div>
          <div className="stat"><span className="stat__label">Live agents</span><span className="stat__value">0</span></div>
        </div>
      </section>

      <section className="section">
        <div className="section__head"><span className="eyebrow">Jump back in</span></div>
        <div className="l-grid l-grid--2col">
          {jump.map((app) => (
            <div className="card card--interactive" key={app.key}>
              <div className="app-tile">
                <span className="app-tile__icon"><svg className="icon icon--lg" aria-hidden="true"><use href={`#${app.icon}`} /></svg></span>
                <div>
                  <div className="app-tile__name">{app.label}</div>
                  <div className="app-tile__desc">{app.desc}</div>
                </div>
              </div>
            </div>
          ))}
        </div>
      </section>

      <section className="section">
        <div className="section__head"><span className="eyebrow">Recent decisions</span></div>
        <div className="card">
          <div className="empty-state">
            <span className="empty-state__icon"><svg className="icon" aria-hidden="true"><use href="#i-app-observability" /></svg></span>
            <div className="empty-state__title">No decisions yet</div>
            <p className="empty-state__body">Once your agents run, their decisions appear here with confidence, cost, and review status.</p>
          </div>
        </div>
      </section>
    </div>
  )
}
