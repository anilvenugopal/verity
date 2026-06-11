import { useEffect, useState, useMemo, useRef, useCallback, type MouseEvent as ReactMouseEvent } from 'react'
import { useHelpPage } from '@/help/useHelp'
import { HELP_PAGES, type HelpPageEntry } from '@/help/pages'

// Module-level singleton — lets non-React code (toasts, route handlers) open/close the panel
// without prop drilling. Same pattern as toastEmitter.
let _setPath: ((path: string | null) => void) | null = null

export const helpDrawer = {
  open(path: string) { _setPath?.(path) },
  close()            { _setPath?.(null) },
}

const MIN_W = 280
const MAX_W = 600
const DEFAULT_W = 380

const GROUPS = ['Reference', 'Forms', 'Workflows', 'How-To', 'Roles'] as const

// Wraps the first matching substring in <mark>. Case-insensitive, first occurrence only.
function Highlight({ text, query }: { text: string; query: string }) {
  if (!query) return <>{text}</>
  const idx = text.toLowerCase().indexOf(query.toLowerCase())
  if (idx === -1) return <>{text}</>
  return (
    <>
      {text.slice(0, idx)}
      <mark className="help-highlight">{text.slice(idx, idx + query.length)}</mark>
      {text.slice(idx + query.length)}
    </>
  )
}

interface HelpItemProps {
  entry: HelpPageEntry
  onClick: () => void
  active?: boolean
  query?: string
  showGroup?: boolean
  setRef?: (el: HTMLButtonElement | null) => void
  onKeyDown?: (e: React.KeyboardEvent<HTMLButtonElement>) => void
}

function HelpItem({ entry, onClick, active, query, showGroup, setRef, onKeyDown }: HelpItemProps) {
  return (
    <button
      type="button"
      ref={setRef}
      className={`help-home__item${active ? ' is-active' : ''}`}
      onClick={onClick}
      title={entry.stub ? 'Coming soon' : undefined}
      disabled={entry.stub}
      onKeyDown={onKeyDown}
    >
      <div className="help-home__item-main">
        <span className="help-home__item-title">
          {query ? <Highlight text={entry.title} query={query} /> : entry.title}
        </span>
        {entry.subtitle && (
          <span className="help-home__item-sub">
            {query ? <Highlight text={entry.subtitle} query={query} /> : entry.subtitle}
          </span>
        )}
      </div>
      {showGroup && <span className="help-home__group-chip">{entry.group}</span>}
      {entry.stub && <span className="help-home__stub-badge">Coming soon</span>}
    </button>
  )
}

function HelpTOC({ lastPage, onNavigate }: { lastPage: string | null; onNavigate: (path: string) => void }) {
  return (
    <div className="help-home">
      {GROUPS.map((group) => {
        const pages = HELP_PAGES.filter((p) => p.group === group)
        return (
          <div key={group} className="help-home__group">
            <div className="help-home__group-label">{group}</div>
            {pages.map((p) => (
              <HelpItem
                key={p.path}
                entry={p}
                active={p.path === lastPage}
                onClick={() => onNavigate(p.path)}
              />
            ))}
          </div>
        )
      })}
    </div>
  )
}

export function HelpDrawer({ onOpenChange }: { onOpenChange?: (open: boolean) => void }) {
  const [path, setPath] = useState<string | null>(null)
  const [query, setQuery] = useState('')
  const [lastPage, setLastPage] = useState<string | null>(null)
  const [width, setWidth] = useState(DEFAULT_W)
  const [resizing, setResizing] = useState(false)
  const widthRef = useRef(DEFAULT_W)

  const isOpen  = path !== null
  const showHome = path === 'home'
  const showPage = isOpen && !showHome

  const loader = useHelpPage(showPage ? (path ?? '') : '')
  const [html, setHtml] = useState<string | null>(null)
  const [loading, setLoading] = useState(false)

  // Scroll position store: saved per path, restored on navigation
  const scrollPositions = useRef<Map<string, number>>(new Map())
  const bodyRef = useRef<HTMLDivElement | null>(null)

  // Refs for keyboard navigation through search results
  const resultRefs = useRef<(HTMLButtonElement | null)[]>([])
  const searchInputRef = useRef<HTMLInputElement | null>(null)

  // Register singleton dispatcher
  useEffect(() => {
    _setPath = setPath
    return () => { _setPath = null }
  }, [])

  // Notify parent of open/closed state (drives the push layout class in AppShell)
  useEffect(() => {
    onOpenChange?.(isOpen)
  }, [isOpen, onOpenChange])

  // Resize — panel is on the right, so dragging left widens (invert delta vs sidebar)
  const onResizeStart = useCallback((e: ReactMouseEvent) => {
    e.preventDefault()
    const startX = e.clientX
    const startW = widthRef.current
    setResizing(true)
    const onMove = (ev: MouseEvent) => {
      const next = Math.min(MAX_W, Math.max(MIN_W, startW - (ev.clientX - startX)))
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

  // Save current scroll before navigating away
  const saveScroll = useCallback(() => {
    if (bodyRef.current && path) {
      scrollPositions.current.set(path, bodyRef.current.scrollTop)
    }
  }, [path])

  // Restore scroll after path change (rAF ensures content has rendered)
  useEffect(() => {
    if (!path) return
    const saved = scrollPositions.current.get(path) ?? 0
    requestAnimationFrame(() => {
      if (bodyRef.current) bodyRef.current.scrollTop = saved
    })
  }, [path])

  // Load HTML content when navigating to a specific page
  useEffect(() => {
    if (!showPage || !loader) { setHtml(null); return }
    setLoading(true)
    loader().then((m) => { setHtml(m.default); setLoading(false) }).catch(() => {
      setHtml('<article class="help-page"><p class="input-hint">Help content unavailable.</p></article>')
      setLoading(false)
    })
  }, [loader, showPage])

  // Track last visited page for active-item state in TOC
  useEffect(() => {
    if (showPage && path) setLastPage(path)
  }, [showPage, path])

  // Clear search when returning to home
  useEffect(() => {
    if (showHome) setQuery('')
  }, [showHome])

  const results = useMemo(() => {
    const q = query.trim().toLowerCase()
    if (!q) return null
    return HELP_PAGES.filter(
      (p) => p.title.toLowerCase().includes(q) || (p.subtitle ?? '').toLowerCase().includes(q),
    )
  }, [query])

  const pageTitle = showPage
    ? (HELP_PAGES.find((p) => p.path === path)?.title ?? 'Help')
    : 'Help'

  const navigateTo = useCallback((targetPath: string) => {
    saveScroll()
    setPath(targetPath)
  }, [saveScroll])

  // Arrow-down on search input moves focus to first result
  const handleSearchKeyDown = (e: React.KeyboardEvent<HTMLInputElement>) => {
    if (e.key === 'ArrowDown' && results && results.length > 0) {
      e.preventDefault()
      resultRefs.current[0]?.focus()
    }
  }

  // Arrow navigation within result list; Escape clears and refocuses search
  const handleResultKeyDown = (index: number) => (e: React.KeyboardEvent<HTMLButtonElement>) => {
    if (e.key === 'ArrowDown') {
      e.preventDefault()
      resultRefs.current[index + 1]?.focus()
    } else if (e.key === 'ArrowUp') {
      e.preventDefault()
      if (index === 0) searchInputRef.current?.focus()
      else resultRefs.current[index - 1]?.focus()
    } else if (e.key === 'Escape') {
      setQuery('')
      searchInputRef.current?.focus()
    }
  }

  return (
    <div
      className={`help-panel${resizing ? ' is-resizing' : ''}`}
      style={isOpen ? { width } : undefined}
    >
      <div className="help-panel__resize-handle" onMouseDown={onResizeStart} />
      <div className="help-panel__wrap">

        {/* Header */}
        <div className="help-panel__header">
          {showPage && (
            <button
              type="button"
              className="btn btn--icon btn--ghost help-panel__back"
              aria-label="Back to help home"
              onClick={() => { saveScroll(); setPath('home') }}
            >
              <svg className="icon" aria-hidden="true"><use href="#i-prev" /></svg>
            </button>
          )}
          <span className="help-panel__title">{pageTitle}</span>
          <button
            type="button"
            className="btn btn--icon btn--ghost"
            aria-label="Close help"
            onClick={() => { saveScroll(); setPath(null) }}
          >
            <svg className="icon" aria-hidden="true"><use href="#i-close" /></svg>
          </button>
        </div>

        {/* Search — home only */}
        {showHome && (
          <div className="help-panel__search">
            <svg className="icon help-panel__search-icon" aria-hidden="true"><use href="#i-search" /></svg>
            <input
              ref={searchInputRef}
              className="help-panel__search-input"
              placeholder="Search help…"
              value={query}
              onChange={(e) => setQuery(e.target.value)}
              onKeyDown={handleSearchKeyDown}
              aria-label="Search help"
            />
            {query && (
              <button
                type="button"
                className="btn btn--icon btn--ghost"
                aria-label="Clear search"
                onClick={() => setQuery('')}
              >
                <svg className="icon" aria-hidden="true"><use href="#i-clear" /></svg>
              </button>
            )}
          </div>
        )}

        {/* Body */}
        <div className="help-panel__body" ref={bodyRef}>
          {showHome && (
            results !== null ? (
              results.length === 0
                ? <p className="help-panel__empty">No results for "{query}"</p>
                : <div className="help-home">
                    {results.map((p, i) => (
                      <HelpItem
                        key={p.path}
                        entry={p}
                        query={query.trim()}
                        showGroup
                        setRef={(el) => { resultRefs.current[i] = el }}
                        onClick={() => { setQuery(''); navigateTo(p.path) }}
                        onKeyDown={handleResultKeyDown(i)}
                      />
                    ))}
                  </div>
            ) : (
              <HelpTOC lastPage={lastPage} onNavigate={navigateTo} />
            )
          )}

          {showPage && loading && <p className="input-hint" style={{ padding: 'var(--space-4)' }}>Loading…</p>}
          {showPage && !loading && html && <div className="help-page-wrap" dangerouslySetInnerHTML={{ __html: html }} />}
          {showPage && !loading && !html && (
            <p className="input-hint" style={{ padding: 'var(--space-4)' }}>No help page found for "{path}".</p>
          )}
        </div>

      </div>
    </div>
  )
}
