import { type KeyboardEvent as ReactKeyboardEvent, useEffect, useMemo, useState } from 'react'
import { useNavigate } from 'react-router-dom'
import { useSession } from '@/auth/useSession'
import { api } from '@/api/client'
import type { Application, IntakeListItem } from '@/api/types'
import { NAV, type NavKind, type NavNode, resolveNav } from './nav'
import './CommandPalette.css'

// Global search (ctrl+J): nav items (apps/pages/actions) + live object results.
// To add a new object type, append one entry to OBJECT_SOURCES.

const NAV_GROUPS: { kind: NavKind; label: string }[] = [
  { kind: 'app', label: 'Apps' },
  { kind: 'page', label: 'Pages' },
  { kind: 'action', label: 'Actions' },
]

// ── live object search ────────────────────────────────────────────────────────

interface ObjectResult {
  key: string
  group: string
  label: string
  hint?: string
  icon: string
  to: string
}

interface ObjectSource {
  group: string
  icon: string
  fetch: () => Promise<Omit<ObjectResult, 'group' | 'icon'>[]>
}

// Extension point — add one entry per object type as its API endpoint becomes available.
//
// Each entry must supply:
//   group  — display label for the result group (e.g. 'Registry items')
//   icon   — sprite id (e.g. 'i-app-registry'); pick the entity icon, not the app icon
//   fetch  — async fn that calls api.get<T[]>(...) and maps rows to
//             { key: string, label: string, hint?: string, to: string }
//             key   : unique, stable — use '<prefix>:<id>' (e.g. 'reg:${r.id}')
//             label : primary display text (name/title)
//             hint  : secondary text shown right-aligned (code, parent name, version…)
//             to    : the detail route (e.g. '/registry/${r.id}')
//
// The hook debounces (200 ms), fetches all sources in parallel, and filters client-side.
// When the API adds server-side text-search params, pass `q` to the fetch call instead.
//
// Example — adding Registry items once /api/registry/items ships:
//   {
//     group: 'Registry items',
//     icon: 'i-app-registry',
//     async fetch() {
//       const items = await api.get<RegistryItem[]>('/api/registry/items')
//       return items.map((r) => ({ key: `reg:${r.id}`, label: r.name, hint: r.version, to: `/registry/${r.id}` }))
//     },
//   },
const OBJECT_SOURCES: ObjectSource[] = [
  {
    group: 'Applications',
    icon: 'i-entity-application',
    async fetch() {
      const items = await api.get<Application[]>('/api/applications')
      return items.map((a) => ({ key: `app:${a.application_id}`, label: a.name, hint: a.code, to: `/applications/${a.application_id}` }))
    },
  },
  {
    group: 'Use cases',
    icon: 'i-entity-task',
    async fetch() {
      const items = await api.get<IntakeListItem[]>('/api/intakes')
      return items.map((i) => ({ key: `intake:${i.intake_id}`, label: i.title, hint: i.application_name, to: `/intakes/${i.intake_id}` }))
    },
  },
]

function useObjectResults(query: string): ObjectResult[] {
  const [results, setResults] = useState<ObjectResult[]>([])

  useEffect(() => {
    const q = query.trim().toLowerCase()
    if (!q) { setResults([]); return }

    let cancelled = false
    const timer = setTimeout(() => {
      Promise.all(
        OBJECT_SOURCES.map(async (src) => {
          const items = await src.fetch()
          return items
            .filter((i) => i.label.toLowerCase().includes(q) || (i.hint?.toLowerCase().includes(q) ?? false))
            .map((i) => ({ ...i, group: src.group, icon: src.icon }))
        }),
      )
        .then((groups) => { if (!cancelled) setResults(groups.flat()) })
        .catch(() => undefined)
    }, 200)

    return () => { cancelled = true; clearTimeout(timer) }
  }, [query])

  return results
}

// ── component ─────────────────────────────────────────────────────────────────

export function CommandPalette({ onClose }: { onClose: () => void }) {
  const navigate = useNavigate()
  const { canDo, hasRole } = useSession()
  const [query, setQuery] = useState('')
  const [active, setActive] = useState(0)

  // Flatten the resolved manifest (incl. children) into searchable leaves.
  const navItems = useMemo(() => {
    const flat: NavNode[] = []
    const walk = (nodes: NavNode[]) =>
      nodes.forEach((n) => { flat.push(n); if (n.children) walk(n.children) })
    walk(resolveNav(NAV, (req) => canDo(req) || hasRole(req)))
    return flat
  }, [canDo, hasRole])

  const q = query.trim().toLowerCase()
  const navMatches = navItems.filter((n) => `${n.label} ${n.desc ?? ''}`.toLowerCase().includes(q))
  const objectResults = useObjectResults(query)

  // Unified keyboard-navigation order: nav items first, then object results.
  const orderedNav = NAV_GROUPS.flatMap(({ kind }) => navMatches.filter((n) => n.kind === kind))
  const totalCount = orderedNav.length + objectResults.length

  useEffect(() => setActive(0), [q])

  useEffect(() => {
    const onKey = (e: KeyboardEvent) => e.key === 'Escape' && onClose()
    document.addEventListener('keydown', onKey)
    return () => document.removeEventListener('keydown', onKey)
  }, [onClose])

  function runNav(n: NavNode) { if (n.to) navigate(n.to); onClose() }
  function runObj(r: ObjectResult) { navigate(r.to); onClose() }

  function onInputKey(e: ReactKeyboardEvent) {
    if (e.key === 'ArrowDown') {
      e.preventDefault(); setActive((a) => Math.min(a + 1, totalCount - 1))
    } else if (e.key === 'ArrowUp') {
      e.preventDefault(); setActive((a) => Math.max(a - 1, 0))
    } else if (e.key === 'Enter') {
      e.preventDefault()
      if (active < orderedNav.length) { const n = orderedNav[active]; if (n) runNav(n) }
      else { const r = objectResults[active - orderedNav.length]; if (r) runObj(r) }
    }
  }

  const noResults = !navMatches.length && !objectResults.length

  return (
    <div className="overlay" onClick={onClose}>
      <div className="modal" role="dialog" aria-modal="true" aria-label="Command palette" onClick={(e) => e.stopPropagation()}>
        <div className="modal__search">
          <svg className="icon" aria-hidden="true"><use href="#i-search" /></svg>
          <input
            autoFocus
            type="text"
            placeholder="Search apps, pages, objects…"
            aria-label="Command palette"
            value={query}
            onChange={(e) => setQuery(e.target.value)}
            onKeyDown={onInputKey}
          />
          <kbd>esc</kbd>
        </div>
        <div className="modal__body">
          {NAV_GROUPS.map(({ kind, label }) => {
            const group = navMatches.filter((n) => n.kind === kind)
            if (!group.length) return null
            return (
              <div key={kind}>
                <div className="pgroup__label"><span className="eyebrow">{label}</span></div>
                {group.map((n) => {
                  const idx = orderedNav.indexOf(n)
                  return (
                    <button
                      key={n.key}
                      className={`presult${idx === active ? ' is-active' : ''}`}
                      onClick={() => runNav(n)}
                      onMouseMove={() => setActive(idx)}
                    >
                      <svg className="icon icon--sm" aria-hidden="true"><use href={`#${n.icon}`} /></svg>
                      <span className="presult__name">{n.label}</span>
                      <span className="presult__hint">{n.kind}</span>
                    </button>
                  )
                })}
              </div>
            )
          })}
          {q && OBJECT_SOURCES.map((src) => {
            const group = objectResults.filter((r) => r.group === src.group)
            if (!group.length) return null
            return (
              <div key={src.group}>
                <div className="pgroup__label"><span className="eyebrow">{src.group}</span></div>
                {group.map((r) => {
                  const idx = orderedNav.length + objectResults.indexOf(r)
                  return (
                    <button
                      key={r.key}
                      className={`presult${idx === active ? ' is-active' : ''}`}
                      onClick={() => runObj(r)}
                      onMouseMove={() => setActive(idx)}
                    >
                      <svg className="icon icon--sm" aria-hidden="true"><use href={`#${r.icon}`} /></svg>
                      <span className="presult__name">{r.label}</span>
                      {r.hint && <span className="presult__hint">{r.hint}</span>}
                    </button>
                  )
                })}
              </div>
            )
          })}
          {noResults && (
            <div className="empty-state"><div className="empty-state__body">No matches.</div></div>
          )}
        </div>
      </div>
    </div>
  )
}
