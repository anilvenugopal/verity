import { BrowserRouter, Navigate, Route, Routes } from 'react-router-dom'
import { SessionProvider } from './auth/SessionContext'
import { useSession } from './auth/useSession'
import { ProtectedRoute } from './auth/ProtectedRoute'
import { SignIn } from './pages/SignIn'
import { AuthCallback } from './pages/AuthCallback'
import { SessionExpiredPage, ForbiddenPage, DisabledPage } from './pages/AuthStatePage'
import { Landing } from './pages/Landing'

// The fail-closed takeovers (session_expired / forbidden / disabled) overlay every route — they
// render above the router when the session is in one of those states (FR-006).
function AppRoutes() {
  const { authState } = useSession()
  if (authState === 'session_expired') return <SessionExpiredPage />
  if (authState === 'disabled') return <DisabledPage />
  if (authState === 'forbidden') return <ForbiddenPage />

  return (
    <Routes>
      <Route path="/signin" element={<SignIn />} />
      <Route path="/auth/callback" element={<AuthCallback />} />
      <Route element={<ProtectedRoute />}>
        <Route path="/" element={<Landing />} />
      </Route>
      <Route path="*" element={<Navigate to="/" replace />} />
    </Routes>
  )
}

export function App() {
  return (
    <BrowserRouter>
      <SessionProvider>
        <AppRoutes />
      </SessionProvider>
    </BrowserRouter>
  )
}
