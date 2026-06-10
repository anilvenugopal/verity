import { type KeyboardEvent, useCallback, useEffect, useRef, useState } from 'react'
import { useLocation, useNavigate } from 'react-router-dom'
import { api } from '@/api/client'
import { onDataChanged } from '@/api/events'
import type { Application, AwaitingApproval, IntakeListItem } from '@/api/types'
import { useSession } from '@/auth/useSession'
import { ReviewBadge } from '@/components/ReviewBadge'
import { NAV, type NavNode, resolveNav } from './nav'

// Per-app sidebar (contextual): renders the active app's children — pages/objects grouped by section
// (top), actions stacked at the bottom (the recorded design). Objects return here as a *query result
// projected into the nav* (MY APPLICATIONS): the rows are fetched, bounded (top 3 + "See all"), and
// injected via resolveNav's postProcess hook so they're RE-GATED — the projection can never surface
// what the affordance gate would hide. Reuses canonical sidebar/nav-item/badge classes — no new CSS.
const MY_APPS_MAX = 3
const MIN_W = 140
const MAX_W = 520
const DEFAULT_W = 280

export function Sidebar({ collapsed, onCollapse }: { collapsed: boolean; onCollapse: () => void }) {
  const { pathname } = useLocation()
  const navigate = useNavigate()
  const { canDo, hasRole, principal } = useSession()
  const [apps, setApps] = useState<Application[]>([])
  const [approvals, setApprovals] = useState<AwaitingApproval[]>([])
  const [intakes, setIntakes] = useState<IntakeListItem[]>([])
  const [width, setWidth] = useState(DEFAULT_W)
  const [resizing, setResizing] = useState(false)
  const widthRef = useRef(DEFAULT_W)

  const onResizeStart = useCallback((e: React.MouseEvent) => {
    e.preventDefault()
    const startX = e.clientX
    const startW = widthRef.current
    setResizing(true)

    const onMove = (ev: MouseEvent) => {
      const next = Math.min(MAX_W, Math.max(MIN_W, startW + ev.clientX - startX))
      widthRef.current = next
      setWidth(next)
    }
    const onUp = () => {
      setResizing(false)
      document.removeEventListener('mousemove', onMove)
      document.removeEventListener('mouseup', onUp)
    }
    document.addEventListener('mousemove', onMove)
    document.addEventListener('mouseup', onUp)
  }, [])

  // Applications drive the MY APPLICATIONS projection + the Applications count badge; the awaiting-me
  // queue drives MY APPROVALS. Both project (bounded, re-gated) into the Intake sidebar.
  useEffect(() => {
    const load = () => {
      api.get<Application[]>('/api/applications').then(setApps).catch(() => setApps([]))
      api.get<AwaitingApproval[]>('/api/approvals/awaiting-me').then(setApprovals).catch(() => setApprovals([]))
      api.get<IntakeListItem[]>('/api/intakes').then(setIntakes).catch(() => setIntakes([]))
    }
    load()
    return onDataChanged(load) // re-fetch after any create/submit/delete/cancel/edit (returns the unsubscribe)
  }, [])

  const myApps = principal ? apps.filter((a) => a.business_owner_actor_id === principal.actor_id) : []
  const myIntakes = principal ? intakes.filter((i) => i.created_by_actor_id === principal.actor_id) : []
  // provider → live count for nav `count` badges (grow as pages gain counts; absent = no badge).
  const counts: Record<string, number> = { applications: apps.length }

  const gate = (req: string) => canDo(req) || hasRole(req)
  const navApps = resolveNav(NAV, gate).filter((n) => n.kind === 'app')
  const active = navApps.find((a) => {
    if (!a.to || a.to === '/' || !a.children?.length) return false
    return pathname.startsWith(a.to) || a.children.some((c) => c.to && pathname.startsWith(c.to))
  })
  if (!active?.children?.length) return null

  // Project MY APPLICATIONS (apps I own) + MY APPROVALS (requests awaiting me) into the Intake
  // sidebar — bounded query-result objects, re-gated by resolveNav's postProcess.
  const projectMyApps = (nodes: NavNode[]): NavNode[] => {
    if (active.key !== 'intake') return nodes
    const objs: NavNode[] = []
    // MY APPLICATIONS — apps I own
    objs.push(...myApps.slice(0, MY_APPS_MAX).map((a): NavNode => ({
      key: `obj-app-${a.application_id}`, kind: 'page', label: a.name,
      icon: 'i-entity-application', to: `/applications/${a.application_id}`, section: 'My applications',
    })))
    if (myApps.length > MY_APPS_MAX) {
      objs.push({ key: 'obj-app-more', kind: 'page', label: 'See all', icon: 'i-next', to: '/applications', section: 'My applications' })
    }
    // MY USE CASES — intakes I created
    objs.push(...myIntakes.slice(0, MY_APPS_MAX).map((i): NavNode => ({
      key: `obj-uc-${i.intake_id}`, kind: 'page', label: i.title,
      icon: 'i-entity-task', to: `/intakes/${i.intake_id}`, section: 'My use cases',
    })))
    if (myIntakes.length > MY_APPS_MAX) {
      objs.push({ key: 'obj-uc-more', kind: 'page', label: 'See all', icon: 'i-next', to: '/usecases', section: 'My use cases' })
    }
    // MY APPROVALS — requests awaiting my sign-off (empty for non-approvers)
    objs.push(...approvals.slice(0, MY_APPS_MAX).map((r): NavNode => ({
      key: `obj-appr-${r.approval_request_id}`, kind: 'page', label: r.name,
      icon: 'i-approve', to: `/applications/${r.application_id}`, section: 'My approvals',
    })))
    // primary object links first (ungrouped), then the MY * projections below
    return [...nodes, ...objs]
  }

  const children = resolveNav(active.children, gate, projectMyApps)
  const pages = children.filter((n) => n.kind !== 'action')
  const actions = children.filter((n) => n.kind === 'action')
  const isActive = (to?: string) => !!to && (pathname === to || pathname.startsWith(`${to}/`))
  const sections = [...new Set(pages.map((p) => p.section ?? ''))]

  const countBadge = (n: NavNode): string | number | undefined => {
    if (n.badge != null) return n.badge
    if (!n.count) return undefined
    const v = counts[n.count.provider]
    if (v == null) return undefined // provider not resolved → no badge (count is optional)
    const cap = n.count.cap
    return cap != null && v > cap ? `${cap}+` : v
  }

  const item = (n: NavNode) => {
    const go = n.to ? () => navigate(n.to!) : undefined
    const badge = countBadge(n)
    // app-object rows carry the application's derived review status (Draft / In review / Rejected / …)
    const objApp = n.key.startsWith('obj-app-') ? myApps.find((a) => `obj-app-${a.application_id}` === n.key) : undefined
    return (
      <div
        key={n.key}
        className={`nav-item${isActive(n.to) ? ' is-active' : ''}`}
        role={go ? 'button' : undefined}
        tabIndex={go ? 0 : undefined}
        aria-current={isActive(n.to) ? 'page' : undefined}
        onClick={go}
        onKeyDown={go ? (e: KeyboardEvent) => (e.key === 'Enter' || e.key === ' ') && go() : undefined}
      >
        <svg className="icon" aria-hidden="true"><use href={`#${n.icon}`} /></svg>
        {n.label}
        {objApp && <><span className="l-spacer" /><ReviewBadge app={objApp} quiet size="sm" /></>}
        {badge != null && <span className="nav-item__badge">{badge}</span>}
      </div>
    )
  }

  return (
    <nav
      className={`app__sidebar${collapsed ? ' app__sidebar--collapsed' : ''}${resizing ? ' is-resizing' : ''}`}
      style={{ width: collapsed ? 0 : width }}
      aria-label={active.label}
    >
      <div className="sidebar__resize-handle" onMouseDown={onResizeStart} />
      <div className="sidebar__header">
        <svg className="icon" aria-hidden="true"><use href={`#${active.icon}`} /></svg>
        <span className="sidebar__app-name">{active.label}</span>
        <button
          className="sidebar__toggle"
          onClick={onCollapse}
          aria-label="Collapse sidebar"
          title="Collapse"
        >
          <svg className="icon" aria-hidden="true"><use href="#i-prev" /></svg>
        </button>
      </div>
      {sections.map((sec) => (
        <div className="sidebar__section" key={sec || 'default'}>
          {sec && <div className="sidebar__section-label">{sec}</div>}
          {pages.filter((p) => (p.section ?? '') === sec).map(item)}
        </div>
      ))}
      {actions.length > 0 && (
        <>
          <span className="l-spacer" />
          <div className="sidebar__section">
            <div className="sidebar__section-label">Actions</div>
            {actions.map(item)}
          </div>
        </>
      )}
    </nav>
  )
}
