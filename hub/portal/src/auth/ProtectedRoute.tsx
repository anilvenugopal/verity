import { Navigate, Outlet, useLocation } from 'react-router-dom'
import { useSession } from './useSession'

// Gates authenticated routes. Loading → spinner; unauthenticated → /signin (preserving `next`);
// otherwise render the route. The session_expired / forbidden / disabled takeovers are rendered
// above the outlet by App (they overlay any route).
export function ProtectedRoute() {
  const { authState } = useSession()
  const location = useLocation()

  if (authState === 'loading') {
    return (
      <div className="loading-screen" role="status" aria-live="polite">
        <span className="spinner" aria-hidden="true" />
        <span className="u-visually-hidden">Loading…</span>
      </div>
    )
  }

  if (authState === 'unauthenticated') {
    const next = encodeURIComponent(location.pathname + location.search)
    return <Navigate to={`/signin?next=${next}`} replace />
  }

  return <Outlet />
}
