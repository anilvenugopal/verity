import { useEffect, useRef, useState } from 'react'
import { useHelpPage } from '@/help/useHelp'

// Module-level singleton — lets non-React code (toasts, route handlers) open/close the drawer
// without prop drilling. Same pattern as toastEmitter.
let _setPath: ((path: string | null) => void) | null = null

export const helpDrawer = {
  open(path: string) { _setPath?.(path) },
  close()            { _setPath?.(null) },
}

export function HelpDrawer() {
  const [path, setPath] = useState<string | null>(null)
  const [html, setHtml] = useState<string | null>(null)
  const [loading, setLoading] = useState(false)
  const dialogRef = useRef<HTMLDialogElement>(null)
  // useHelpPage is a pure manifest walk — safe to call unconditionally despite the use* name
  const loader = useHelpPage(path ?? '')

  // Register singleton dispatcher
  useEffect(() => {
    _setPath = setPath
    return () => { _setPath = null }
  }, [])

  // Open / close the <dialog> when path changes
  useEffect(() => {
    const el = dialogRef.current
    if (!el) return
    if (path) {
      if (!el.open) el.showModal()
    } else {
      if (el.open) el.close()
      setHtml(null)
    }
  }, [path])

  // Load HTML content when loader is available
  useEffect(() => {
    if (!loader) { setHtml(null); return }
    setLoading(true)
    loader().then((m) => { setHtml(m.default); setLoading(false) }).catch(() => {
      setHtml('<article class="help-page"><p class="input-hint">Help content unavailable.</p></article>')
      setLoading(false)
    })
  }, [loader])

  // Close on Escape (native dialog handles this; we just sync state)
  function onClose() { setPath(null) }

  return (
    <dialog ref={dialogRef} className="help-drawer" onClose={onClose} onClick={(e) => {
      // close on backdrop click (the dialog element itself, not its content)
      if (e.target === dialogRef.current) helpDrawer.close()
    }}>
      <div className="help-drawer__inner">
        <button className="help-drawer__close" aria-label="Close help" onClick={helpDrawer.close}>
          <svg className="icon" aria-hidden="true"><use href="#i-close" /></svg>
        </button>
        {loading && <p className="input-hint">Loading…</p>}
        {!loading && html && <div dangerouslySetInnerHTML={{ __html: html }} />}
        {!loading && !html && path && <p className="input-hint">No help page found for "{path}".</p>}
      </div>
    </dialog>
  )
}
