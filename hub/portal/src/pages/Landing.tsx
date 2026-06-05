import { useSession } from '@/auth/useSession'
import { AccountMenu } from '@/shell/AccountMenu'
import './Landing.css'

// US1 stub landing — enough to prove sign-in lands you in the app and the account menu / sign-out
// work. Built on the master app-shell primitives (.app/.app__topbar/.app__canvas). The full
// five-region shell + landing is US2 (T024–T030), which replaces this.
export function Landing() {
  const { principal } = useSession()
  if (!principal) return null

  return (
    <div className="app">
      <header className="app__topbar">
        <a className="landing__brand" href="/" aria-label="Verity — Home">
          <img className="wordmark wordmark--light" src="/assets/verity-wordmark-dark.png" alt="Verity" width={74} height={22} />
          <img className="wordmark wordmark--dark" src="/assets/verity-wordmark-white.png" alt="" aria-hidden="true" width={74} height={22} />
        </a>
        <span className="l-spacer" />
        <div className="landing__utils">
          <AccountMenu principal={principal} />
        </div>
      </header>
      <div className="app__body">
        <main className="app__canvas">
          <div className="landing__pad">
            <h1 className="landing__welcome">Welcome, {principal.display_name}</h1>
            <p className="landing__sub">
              You're signed in to Verity{principal.is_mock ? ' (mock auth · local dev)' : ''}. The full
              home page and application shell arrive in the next milestone.
            </p>
          </div>
        </main>
      </div>
    </div>
  )
}
