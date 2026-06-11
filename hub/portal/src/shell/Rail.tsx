import type { KeyboardEvent } from 'react'
import { useLocation, useNavigate } from 'react-router-dom'
import { useSession } from '@/auth/useSession'
import { NAV, resolveNav } from './nav'

// The app rail — rendered from the resolved nav manifest (affordance-filtered). `.rail-app-icon` is
// canonical and built for a <div>, so we use role=button rather than restyle it.
// Clicking the already-active app icon toggles the sidebar (expand/collapse), matching the
// VSCode/standard pattern where the active sidebar button is the collapse trigger.
export function Rail({ onLauncher, sidebarCollapsed, onToggleSidebar }: {
  onLauncher: () => void
  sidebarCollapsed: boolean
  onToggleSidebar: () => void
}) {
  const navigate = useNavigate()
  const { pathname } = useLocation()
  const { canDo, hasRole } = useSession()
  const apps = resolveNav(NAV, (req) => canDo(req) || hasRole(req)).filter((n) => n.kind === 'app')

  // An app is "active" if the current path is its own route OR any of its children's routes.
  // This ensures clicking the rail icon always toggles the sidebar when you're anywhere in the
  // app's subtree — never navigates away from a child page (e.g. /usecases is inside Intake).
  const isActive = (app: { to?: string; children?: { to?: string }[]; ownedPaths?: string[] }) => {
    if (!app.to) return false
    const owns = (to: string) => to === '/' ? pathname === '/' : pathname.startsWith(to)
    return owns(app.to) ||
      (app.children?.some((c) => c.to && owns(c.to)) ?? false) ||
      (app.ownedPaths?.some(owns) ?? false)
  }
  const activate = (fn: () => void) => (e: KeyboardEvent) => (e.key === 'Enter' || e.key === ' ') && fn()

  return (
    <nav className="app__left-rail" aria-label="Apps">
      <div className="rail-apps">
        {apps.map((app) => {
          const active = isActive(app)
          const hasSidebar = !!app.children?.length
          const go = () => {
            if (active && hasSidebar) onToggleSidebar()
            else if (app.to) navigate(app.to)
          }
          return (
            <div
              key={app.key}
              className={`rail-app-icon${active ? ' is-active' : ''}`}
              role="button"
              tabIndex={0}
              data-tooltip={
                active && hasSidebar
                  ? sidebarCollapsed ? `${app.label} — expand sidebar` : `${app.label} — collapse sidebar`
                  : app.desc ? `${app.label} — ${app.desc}` : app.label
              }
              aria-current={active ? 'page' : undefined}
              onClick={go}
              onKeyDown={activate(go)}
            >
              <svg className="icon" aria-hidden="true"><use href={`#${app.icon}`} /></svg>
            </div>
          )
        })}
      </div>
      <span className="l-spacer" />
      <div className="rail-app-icon" role="button" tabIndex={0} data-tooltip="App launcher" onClick={onLauncher} onKeyDown={activate(onLauncher)}>
        <svg className="icon" aria-hidden="true"><use href="#i-app-launcher" /></svg>
      </div>
      <div className="rail-app-icon" role="button" tabIndex={0} data-tooltip="Settings">
        <svg className="icon" aria-hidden="true"><use href="#i-app-settings" /></svg>
      </div>
    </nav>
  )
}
