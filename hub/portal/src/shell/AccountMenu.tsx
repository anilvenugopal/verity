import { useEffect, useRef, useState } from 'react'
import { useNavigate } from 'react-router-dom'
import { api } from '@/api/client'
import { useSession } from '@/auth/useSession'
import type { Principal } from '@/api/types'
import './AccountMenu.css'

function initials(name: string): string {
  const parts = name.trim().split(/\s+/)
  return ((parts[0]?.[0] ?? '') + (parts[1]?.[0] ?? '')).toUpperCase() || '?'
}

function roleLabel(code: string): string {
  return code
    .split('_')
    .map((w) => (w === 'ai' ? 'AI' : w.charAt(0).toUpperCase() + w.slice(1)))
    .join(' ')
}

export function AccountMenu({ principal }: { principal: Principal }) {
  const [open, setOpen] = useState(false)
  const { refresh } = useSession()
  const navigate = useNavigate()
  const ref = useRef<HTMLDivElement>(null)

  useEffect(() => {
    if (!open) return
    const onKey = (e: KeyboardEvent) => e.key === 'Escape' && setOpen(false)
    const onClick = (e: MouseEvent) => {
      if (ref.current && !ref.current.contains(e.target as Node)) setOpen(false)
    }
    document.addEventListener('keydown', onKey)
    document.addEventListener('mousedown', onClick)
    return () => {
      document.removeEventListener('keydown', onKey)
      document.removeEventListener('mousedown', onClick)
    }
  }, [open])

  async function signOut() {
    await api.post('/auth/logout')
    await refresh()
    navigate('/signin', { replace: true })
  }

  return (
    <div className="account" ref={ref}>
      <button
        className={`avatar${open ? ' is-open' : ''}`}
        title={principal.display_name}
        aria-haspopup="menu"
        aria-expanded={open}
        onClick={() => setOpen((v) => !v)}
      >
        {initials(principal.display_name)}
      </button>

      {open && (
        <div className="account__menu" role="menu" aria-label="Account">
          {principal.is_mock && (
            <div className="menu__mock">
              <svg className="icon" aria-hidden="true"><use href="#i-lock" /></svg>
              Mock · {principal.display_name} — synthetic principal
            </div>
          )}
          <div className="menu__head">
            <span className="avatar">{initials(principal.display_name)}</span>
            <div>
              <div className="menu__name">{principal.display_name}</div>
              <div className="menu__email">{principal.email ?? '—'}</div>
            </div>
          </div>

          <div className="menu__section">
            <div className="eyebrow menu__label">Platform roles</div>
            {principal.platform_roles.length ? (
              <div className="roles">
                {principal.platform_roles.map((r) => (
                  <span className="chip chip--static" key={r}>{roleLabel(r)}</span>
                ))}
              </div>
            ) : (
              <div className="menu__empty">No platform roles.</div>
            )}
          </div>

          <div className="menu__section">
            <div className="eyebrow menu__label">App-team roles</div>
            {principal.app_team_roles.length ? (
              // app_team_roles is [] in this MVP (deferred). When surfaced later, decide whether
              // .chip--static needs a neutral variant — through the design-system review.
              <div className="roles">
                {principal.app_team_roles.map((r) => (
                  <span className="chip chip--static" key={`${r.application_id}:${r.role_code}`}>
                    {r.application_name} · {roleLabel(r.role_code)}
                  </span>
                ))}
              </div>
            ) : (
              <div className="menu__empty">None.</div>
            )}
          </div>

          <div className="menu__items">
            <button className="menu__item menu__item--danger" onClick={signOut}>
              <svg className="icon" aria-hidden="true"><use href="#i-open-editor" /></svg>
              Sign out
            </button>
          </div>
        </div>
      )}
    </div>
  )
}
