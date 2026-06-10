import { useEffect } from 'react'
import { useNavigate } from 'react-router-dom'
import { useSession } from '@/auth/useSession'

// Entra OIDC return route. The backend /auth/callback is currently a scaffold (redirects to
// /signin); this component calls it on mount, then refreshes the session and routes home on
// success, or returns to /signin on failure. No IdP error strings are reflected in the UI.
export function AuthCallback() {
  const navigate = useNavigate()
  const { refresh } = useSession()

  useEffect(() => {
    let cancelled = false
    ;(async () => {
      try {
        const res = await fetch(`/auth/callback${window.location.search}`, { credentials: 'include' })
        if (cancelled) return
        if (res.ok || res.redirected) {
          await refresh()
          navigate('/', { replace: true })
        } else {
          navigate('/signin', { replace: true })
        }
      } catch {
        if (!cancelled) navigate('/signin', { replace: true })
      }
    })()
    return () => {
      cancelled = true
    }
  }, [navigate, refresh])

  return (
    <div className="loading-screen" role="status" aria-live="polite">
      <span className="spinner" aria-hidden="true" />
      <span className="u-visually-hidden">Completing sign-in…</span>
    </div>
  )
}
