import type { KeyboardEvent } from 'react'
import { useLocation, useNavigate } from 'react-router-dom'
import { useSession } from '@/auth/useSession'
import { NAV, resolveNav } from './nav'

// The app rail — rendered from the resolved nav manifest (affordance-filtered). `.rail-app-icon` is
// canonical and built for a <div>, so we use role=button rather than restyle it.
export function Rail({ onLauncher }: { onLauncher: () => void }) {
  const navigate = useNavigate()
  const { pathname } = useLocation()
  const { canDo, hasRole } = useSession()
  const apps = resolveNav(NAV, (req) => canDo(req) || hasRole(req)).filter((n) => n.kind === 'app')

  const isActive = (to?: string) => (!to ? false : to === '/' ? pathname === '/' : pathname.startsWith(to))
  const activate = (fn: () => void) => (e: KeyboardEvent) => (e.key === 'Enter' || e.key === ' ') && fn()

  return (
    <nav className="app__left-rail" aria-label="Apps">
      <div className="rail-apps">
        {apps.map((app) => {
          const go = () => app.to && navigate(app.to)
          return (
            <div
              key={app.key}
              className={`rail-app-icon${isActive(app.to) ? ' is-active' : ''}`}
              role="button"
              tabIndex={0}
              data-tooltip={app.desc ? `${app.label} — ${app.desc}` : app.label}
              aria-current={isActive(app.to) ? 'page' : undefined}
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
