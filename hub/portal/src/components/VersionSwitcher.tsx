import { useEffect, useRef, useState } from 'react'
import { useNavigate } from 'react-router-dom'
import '../pages/registry/RegistryDetail.css'

const STAGE_ORDER: Record<string, number> = {
  champion: 5, certified: 4, approved: 3, review: 2, draft: 1, deprecated: 0,
}

function parseSemver(s: string | null | undefined): [number, number, number] {
  if (!s) return [0, 0, 0]
  const p = s.split('.').map(Number)
  return [p[0] ?? 0, p[1] ?? 0, p[2] ?? 0]
}

function compareSemverDesc(a: string | null | undefined, b: string | null | undefined): number {
  const [am, an, ap] = parseSemver(a)
  const [bm, bn, bp] = parseSemver(b)
  return bm - am || bn - an || bp - ap
}

export interface VersionEntry {
  id: string
  semver: string | null
  stage?: string | null
  hint?: string | null
}

interface Props {
  versions: VersionEntry[]
  currentId: string
  getTo: (id: string) => string
}

function StageBadge({ stage }: { stage: string }) {
  return (
    <span className={`badge badge--${stage}`}>
      <span className="badge__dot" />
      <span className="badge__label">{stage}</span>
    </span>
  )
}

export function VersionSwitcher({ versions, currentId, getTo }: Props) {
  const [open, setOpen] = useState(false)
  const ref = useRef<HTMLDivElement>(null)
  const navigate = useNavigate()

  const sorted = [...versions].sort((a, b) => {
    const sa = STAGE_ORDER[a.stage ?? ''] ?? -1
    const sb = STAGE_ORDER[b.stage ?? ''] ?? -1
    return sb - sa || compareSemverDesc(a.semver, b.semver)
  })

  const current = versions.find((v) => v.id === currentId)

  useEffect(() => {
    if (!open) return
    const handler = (e: MouseEvent) => {
      if (ref.current && !ref.current.contains(e.target as Node)) setOpen(false)
    }
    document.addEventListener('mousedown', handler)
    return () => document.removeEventListener('mousedown', handler)
  }, [open])

  useEffect(() => {
    setOpen(false)
  }, [currentId])

  return (
    <div className="version-switcher" ref={ref}>
      <button className="version-switcher__btn" onClick={() => setOpen((v) => !v)} aria-haspopup="listbox">
        v{current?.semver ?? '—'}
        {current?.stage && <StageBadge stage={current.stage} />}
        <svg className="icon" aria-hidden="true" style={{ transform: open ? 'rotate(180deg)' : undefined, transition: 'transform 0.15s' }}>
          <use href="#i-chevron-down" />
        </svg>
      </button>
      {open && (
        <div className="version-switcher__panel" role="listbox">
          {sorted.map((v) => (
            <div
              key={v.id}
              role="option"
              aria-selected={v.id === currentId}
              className={`version-switcher__row${v.id === currentId ? ' version-switcher__row--current' : ''}`}
              onClick={() => { setOpen(false); if (v.id !== currentId) navigate(getTo(v.id)) }}
            >
              <span className="version-switcher__semver">v{v.semver ?? '—'}</span>
              {v.stage && <StageBadge stage={v.stage} />}
              {v.hint && <span className="version-switcher__hint">{v.hint}</span>}
            </div>
          ))}
        </div>
      )}
    </div>
  )
}
