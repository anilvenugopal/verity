import { useEffect, useRef, useState } from 'react'
import type { Application } from '@/api/types'

interface Props {
  apps: Application[]
  selectedId: string | null
  selectedName: string | null
  selectedCode: string | null
  onSelect: (id: string | null, name: string | null, code: string | null) => void
}

export function AppScopePicker({ apps, selectedId, selectedName, selectedCode, onSelect }: Props) {
  const [open, setOpen] = useState(false)
  const ref = useRef<HTMLDivElement>(null)

  useEffect(() => {
    if (!open) return
    const handler = (e: MouseEvent) => {
      if (ref.current && !ref.current.contains(e.target as Node)) setOpen(false)
    }
    document.addEventListener('mousedown', handler)
    return () => document.removeEventListener('mousedown', handler)
  }, [open])

  const select = (id: string | null, name: string | null, code: string | null) => {
    setOpen(false)
    onSelect(id, name, code)
  }

  return (
    <div className="app-scope-picker" ref={ref}>
      <button
        className="app-scope-picker__btn"
        onClick={() => setOpen((v) => !v)}
        aria-haspopup="listbox"
        aria-expanded={open}
      >
        {selectedId ? (
          <>
            {selectedCode && <span className="chip chip--code chip--xs">{selectedCode}</span>}
            <span className="app-scope-picker__label">{selectedName ?? selectedId}</span>
          </>
        ) : (
          <span className="app-scope-picker__label app-scope-picker__label--all">All applications</span>
        )}
        <svg className="icon" aria-hidden="true" style={{ transform: open ? 'rotate(180deg)' : undefined, transition: 'transform 0.15s' }}>
          <use href="#i-chevron-down" />
        </svg>
      </button>
      {open && (
        <div className="app-scope-picker__panel" role="listbox">
          <div
            role="option"
            aria-selected={!selectedId}
            className={`app-scope-picker__row${!selectedId ? ' app-scope-picker__row--selected' : ''}`}
            onClick={() => select(null, null, null)}
          >
            <span className="app-scope-picker__row-name">All applications</span>
          </div>
          {apps.map((a) => (
            <div
              key={a.application_id}
              role="option"
              aria-selected={a.application_id === selectedId}
              className={`app-scope-picker__row${a.application_id === selectedId ? ' app-scope-picker__row--selected' : ''}`}
              onClick={() => select(a.application_id, a.name, a.code)}
            >
              <span className="chip chip--code chip--xs">{a.code}</span>
              <span className="app-scope-picker__row-name">{a.name}</span>
            </div>
          ))}
        </div>
      )}
    </div>
  )
}
