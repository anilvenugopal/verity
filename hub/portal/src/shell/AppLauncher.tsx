import { useEffect, useState } from 'react'
import { useNavigate } from 'react-router-dom'
import { useSession } from '@/auth/useSession'
import { NAV, type NavNode, resolveNav } from './nav'

// App-launcher modal (FR-011): the resolved app set, searchable, close on Esc / overlay click.
export function AppLauncher({ onClose }: { onClose: () => void }) {
  const navigate = useNavigate()
  const { canDo, hasRole } = useSession()
  const apps = resolveNav(NAV, (req) => canDo(req) || hasRole(req)).filter((n) => n.kind === 'app')
  const [query, setQuery] = useState('')

  useEffect(() => {
    const onKey = (e: KeyboardEvent) => e.key === 'Escape' && onClose()
    document.addEventListener('keydown', onKey)
    return () => document.removeEventListener('keydown', onKey)
  }, [onClose])

  const shown = apps.filter((a) => `${a.label} ${a.desc ?? ''}`.toLowerCase().includes(query.toLowerCase()))

  function open(app: NavNode) {
    if (app.to) navigate(app.to)
    onClose()
  }

  return (
    <div className="overlay" onClick={onClose}>
      <div className="modal" role="dialog" aria-modal="true" aria-label="App launcher" onClick={(e) => e.stopPropagation()}>
        <div className="modal__search">
          <svg className="icon" aria-hidden="true"><use href="#i-search" /></svg>
          <input
            autoFocus
            type="text"
            placeholder="Search apps…"
            aria-label="Search apps"
            value={query}
            onChange={(e) => setQuery(e.target.value)}
          />
          <button className="btn btn--icon btn--ghost" onClick={onClose} aria-label="Close">
            <svg className="icon icon--sm" aria-hidden="true"><use href="#i-clear" /></svg>
          </button>
        </div>
        {shown.length ? (
          <div className="modal__grid">
            {shown.map((app) => (
              <button key={app.key} className="launch-tile" onClick={() => open(app)}>
                <span className="launch-tile__icon"><svg className="icon icon--lg" aria-hidden="true"><use href={`#${app.icon}`} /></svg></span>
                <span className="launch-tile__name">{app.label}</span>
                {app.desc && <span className="launch-tile__desc">{app.desc}</span>}
              </button>
            ))}
          </div>
        ) : (
          <div className="empty-state"><div className="empty-state__body">No matches.</div></div>
        )}
      </div>
    </div>
  )
}
