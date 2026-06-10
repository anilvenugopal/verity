import { useEffect, useState } from 'react'
import { useNavigate, useSearchParams } from 'react-router-dom'
import { api } from '@/api/client'
import { useSession } from '@/auth/useSession'
import './SignIn.css'

const IS_MOCK =
  import.meta.env.VITE_AUTH_MODE === 'mock' && import.meta.env.VITE_VERITY_ENV === 'local'

// Allow-list the post-login redirect: only same-app absolute paths, never an external URL.
function safeNext(raw: string | null): string {
  if (!raw) return '/'
  if (raw.startsWith('/') && !raw.startsWith('//')) return raw
  return '/'
}

const ERROR_COPY: Record<string, string> = {
  use_mock: 'Microsoft sign-in is not configured in local dev — use the Local Dev option below.',
  entra_not_configured: 'Microsoft sign-in is not configured yet.',
}

export function SignIn() {
  const navigate = useNavigate()
  const [params] = useSearchParams()
  const { refresh } = useSession()
  const [busy, setBusy] = useState(false)
  const [allRoles, setAllRoles] = useState<string[]>([])
  const [picked, setPicked] = useState<Set<string>>(
    () => new Set(['ai_governance', 'security', 'viewer']),
  )
  const next = safeNext(params.get('next'))
  const error = params.get('error')

  // Load the selectable role vocabulary (local-dev only) — the choices come from the DB.
  useEffect(() => {
    if (!IS_MOCK) return
    api
      .get<{ roles: string[] }>('/auth/roles')
      .then((res) => setAllRoles(res.roles))
      .catch(() => setAllRoles([]))
  }, [])

  function toggleRole(role: string) {
    setPicked((prev) => {
      const copy = new Set(prev)
      if (copy.has(role)) copy.delete(role)
      else copy.add(role)
      return copy
    })
  }

  async function continueAsLocalDev() {
    setBusy(true)
    try {
      await api.post('/auth/mock', { roles: [...picked] })
      await refresh()
      navigate(next, { replace: true })
    } finally {
      setBusy(false)
    }
  }

  return (
    <div className="auth-screen">
      <div className="auth">
        <img className="wordmark wordmark--lg wordmark--light auth__logo" src="/assets/verity-wordmark-dark.png" alt="Verity" />
        <img className="wordmark wordmark--lg wordmark--dark auth__logo" src="/assets/verity-wordmark-white.png" alt="" aria-hidden="true" />
        <div className="auth__title">Sign in to Verity</div>
        <div className="auth__sub">Governance for regulated AI</div>

        <a className="btn btn--primary btn--lg auth__btn" href="/auth/login">
          <svg className="icon icon--sm" aria-hidden="true"><use href="#i-open-editor" /></svg>
          Sign in with Microsoft
        </a>
        <p className="auth__note">
          You'll be redirected to your organization's Microsoft sign-in. Verity never sees your
          password — your identity is provisioned on first sign-in, and your <strong>roles come from
          Verity</strong>, not from the sign-in token.
        </p>

        {error && ERROR_COPY[error] && (
          <div className="callout callout--warning auth__alert">
            <div className="callout__body">{ERROR_COPY[error]}</div>
          </div>
        )}

        {IS_MOCK && (
          <>
            <div className="auth__divider">local development only</div>
            <div className="mock">
              <span className="mock__tag">
                <svg className="icon" aria-hidden="true"><use href="#i-lock" /></svg>
                Mock auth · local dev
              </span>
              <p className="mock__text">
                Sign in as a synthetic principal with the roles you choose — it flows through the same
                provisioning and action gate as production. Guardrailed to <code>VERITY_ENV=local</code>.
              </p>
              <div className="eyebrow mock__roles-label">Roles</div>
              <div className="chip-group" role="group" aria-label="Roles to sign in with">
                {allRoles.map((r) => (
                  <button
                    type="button"
                    key={r}
                    className={`chip${picked.has(r) ? ' is-selected' : ''}`}
                    aria-pressed={picked.has(r)}
                    onClick={() => toggleRole(r)}
                  >
                    {r}
                  </button>
                ))}
              </div>
              <button
                className="btn btn--secondary btn--md mock__go"
                onClick={continueAsLocalDev}
                disabled={busy || picked.size === 0}
              >
                {busy ? 'Signing in…' : `Continue as Local Dev (${picked.size})`}
              </button>
            </div>
          </>
        )}
      </div>
    </div>
  )
}
