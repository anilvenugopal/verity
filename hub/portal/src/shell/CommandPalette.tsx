import { useEffect, useMemo, useState } from 'react'
import { useNavigate } from 'react-router-dom'
import { useSession } from '@/auth/useSession'
import { NAV, type NavKind, type NavNode, resolveNav } from './nav'
import './CommandPalette.css'

// Global search (⌘J): a grouped, searchable LIST across the resolved nav — apps, pages, actions
// (and objects later, injected via the 20% hook). Reuses the approved overlay/modal/modal__search.
const GROUPS: { kind: NavKind; label: string }[] = [
  { kind: 'app', label: 'Apps' },
  { kind: 'page', label: 'Pages' },
  { kind: 'action', label: 'Actions' },
]

export function CommandPalette({ onClose }: { onClose: () => void }) {
  const navigate = useNavigate()
  const { canDo, hasRole } = useSession()
  const [query, setQuery] = useState('')

  // Flatten the resolved manifest (incl. children) into searchable leaves.
  const items = useMemo(() => {
    const flat: NavNode[] = []
    const walk = (nodes: NavNode[]) =>
      nodes.forEach((n) => {
        flat.push(n)
        if (n.children) walk(n.children)
      })
    walk(resolveNav(NAV, (req) => canDo(req) || hasRole(req)))
    return flat
  }, [canDo, hasRole])

  const q = query.trim().toLowerCase()
  const matches = items.filter((n) => `${n.label} ${n.desc ?? ''}`.toLowerCase().includes(q))

  useEffect(() => {
    const onKey = (e: KeyboardEvent) => e.key === 'Escape' && onClose()
    document.addEventListener('keydown', onKey)
    return () => document.removeEventListener('keydown', onKey)
  }, [onClose])

  function run(n: NavNode) {
    if (n.to) navigate(n.to) // pages/apps navigate; actions are wired in US3
    onClose()
  }

  return (
    <div className="overlay" onClick={onClose}>
      <div className="modal" role="dialog" aria-modal="true" aria-label="Command palette" onClick={(e) => e.stopPropagation()}>
        <div className="modal__search">
          <svg className="icon" aria-hidden="true"><use href="#i-search" /></svg>
          <input
            autoFocus
            type="text"
            placeholder="Search apps, pages, actions…"
            aria-label="Command palette"
            value={query}
            onChange={(e) => setQuery(e.target.value)}
          />
          <kbd>esc</kbd>
        </div>
        <div className="modal__body">
          {GROUPS.map(({ kind, label }) => {
            const group = matches.filter((n) => n.kind === kind)
            if (!group.length) return null
            return (
              <div key={kind}>
                <div className="pgroup__label"><span className="eyebrow">{label}</span></div>
                {group.map((n) => (
                  <button key={n.key} className="presult" onClick={() => run(n)}>
                    <svg className="icon icon--sm" aria-hidden="true"><use href={`#${n.icon}`} /></svg>
                    <span className="presult__name">{n.label}</span>
                    <span className="presult__hint">{n.kind}</span>
                  </button>
                ))}
              </div>
            )
          })}
          {!matches.length && (
            <div className="empty-state"><div className="empty-state__body">No matches.</div></div>
          )}
        </div>
      </div>
    </div>
  )
}
