import { BrowserRouter, Navigate, Route, Routes, useParams } from 'react-router-dom'
import { SessionProvider } from './auth/SessionContext'
import { useSession } from './auth/useSession'
import { ProtectedRoute } from './auth/ProtectedRoute'
import { AppShell } from './shell/AppShell'
import { ToastProvider } from './shell/ToastContext'
import { Toast } from './shell/Toast'
import { AppErrorBoundary } from './shell/AppErrorBoundary'
import { ErrorScreen } from './shell/ErrorScreen'
import { helpDrawer } from './shell/HelpDrawer'
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

// Deep-link support for help pages: /help/forms.assessment → opens drawer at that path
function HelpRoute() {
  const { '*': path } = useParams()
  if (path) helpDrawer.open(path)
  return <Navigate to="/" replace />
}

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
          <Route path="/help/*" element={<HelpRoute />} />
        </Route>
      </Route>
      <Route path="/forbidden" element={<ErrorScreen title="Access denied" detail="You don't have permission to view this." action={{ label: 'Go home', to: '/' }} />} />
      <Route path="*" element={<ErrorScreen title="Page not found" detail="This page doesn't exist." action={{ label: 'Go home', to: '/' }} />} />
    </Routes>
  )
}

export function App() {
  return (
    <BrowserRouter>
      <ToastProvider>
        <AppErrorBoundary>
          <SessionProvider>
            <AppRoutes />
          </SessionProvider>
        </AppErrorBoundary>
        <Toast />
      </ToastProvider>
    </BrowserRouter>
  )
}
