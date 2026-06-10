import { BrowserRouter, Navigate, Route, Routes } from 'react-router-dom'
import { SessionProvider } from './auth/SessionContext'
import { useSession } from './auth/useSession'
import { ProtectedRoute } from './auth/ProtectedRoute'
import { AppShell } from './shell/AppShell'
import { ApplicationsList } from './pages/applications/ApplicationsList'
import { OnboardForm } from './pages/applications/OnboardForm'
import { ApplicationWorkspace } from './pages/applications/ApplicationWorkspace'
import { ApprovalRedirect } from './pages/applications/ApprovalRedirect'
import { IntakeCreate } from './pages/intakes/IntakeCreate'
import { IntakeDetail } from './pages/intakes/IntakeDetail'
import { UseCasesList } from './pages/intakes/UseCasesList'
import { ComplianceModel } from './pages/compliance/ComplianceModel'
import { ComplianceRequirement } from './pages/compliance/ComplianceRequirement'
import { RegistryList } from './pages/registry/RegistryList'
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
        <Route element={<AppShell />}>
          <Route path="/" element={<Landing />} />
          <Route path="/applications" element={<ApplicationsList />} />
          <Route path="/applications/new" element={<OnboardForm />} />
          <Route path="/applications/:id/edit" element={<OnboardForm />} />
          <Route path="/applications/:id" element={<ApplicationWorkspace />} />
          <Route path="/applications/:appId/intakes/new" element={<IntakeCreate />} />
          <Route path="/usecases" element={<UseCasesList />} />
          <Route path="/intakes/new" element={<IntakeCreate />} />
          <Route path="/intakes/:id/edit" element={<IntakeCreate />} />
          <Route path="/intakes/:id" element={<IntakeDetail />} />
          <Route path="/approvals/:id" element={<ApprovalRedirect />} />
          <Route path="/compliance" element={<Navigate to="/compliance/model" replace />} />
          <Route path="/compliance/model" element={<ComplianceModel />} />
          <Route path="/compliance/requirements/:code" element={<ComplianceRequirement />} />
          <Route path="/registry" element={<RegistryList />} />
        </Route>
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
