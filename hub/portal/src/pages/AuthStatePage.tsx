import './AuthStatePage.css'

type Variant = 'session_expired' | 'forbidden' | 'disabled'

interface Props {
  variant: Variant
  requiredRole?: string
}

// Full-screen, fail-closed takeover — faithful to specs/ui/kit/pages/auth-states.html.
export function AuthStatePage({ variant, requiredRole = 'ai_governance' }: Props) {
  if (variant === 'session_expired') {
    return (
      <div className="takeover">
        <div className="card takeover__card">
          <div className="state__icon state__icon--warn"><svg className="icon" aria-hidden="true"><use href="#i-recent" /></svg></div>
          <div className="state__code">session</div>
          <div className="state__title">Your session has expired</div>
          <p className="state__body">For your security you've been signed out. Sign in again to continue — your work is saved.</p>
          <div className="state__actions">
            <a className="btn btn--primary btn--md" href="/signin">
              <svg className="icon icon--sm" aria-hidden="true"><use href="#i-open-editor" /></svg>
              Sign in with Microsoft
            </a>
          </div>
        </div>
      </div>
    )
  }

  if (variant === 'forbidden') {
    return (
      <div className="takeover">
        <div className="card takeover__card">
          <div className="state__icon state__icon--err"><svg className="icon" aria-hidden="true"><use href="#i-lock" /></svg></div>
          <div className="state__code">403 · forbidden</div>
          <div className="state__title">You don't have permission</div>
          <p className="state__body">
            This action requires the <code>{requiredRole}</code> role. Ask a workspace admin to grant
            it — role changes take effect within seconds.
          </p>
          <div className="state__actions">
            <button className="btn btn--secondary btn--md" onClick={() => history.back()}>Back</button>
            <button className="btn btn--ghost btn--md">Request access</button>
          </div>
        </div>
      </div>
    )
  }

  return (
    <div className="takeover">
      <div className="state">
        <div className="state__icon state__icon--neutral"><svg className="icon" aria-hidden="true"><use href="#i-state-deprecated" /></svg></div>
        <div className="state__code">account</div>
        <div className="state__title">Your account is disabled</div>
        <p className="state__body">An administrator has disabled your access to Verity. Contact them to restore it.</p>
        <div className="state__actions">
          <button className="btn btn--ghost btn--md">Contact administrator</button>
        </div>
      </div>
    </div>
  )
}

export const SessionExpiredPage = () => <AuthStatePage variant="session_expired" />
export const ForbiddenPage = () => <AuthStatePage variant="forbidden" />
export const DisabledPage = () => <AuthStatePage variant="disabled" />
