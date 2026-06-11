import { useSession } from '@/auth/useSession'
import { AccountMenu } from './AccountMenu'
import { helpDrawer } from './HelpDrawer'

// Topbar: wordmark · breadcrumb · spacer · utils (search, help, account menu). Reuses canonical
// topbar__logo / breadcrumb / topbar__utils / btn / search-field; row layout is page-local.
// Theme is now controlled via Preferences (AccountMenu → PreferencesModal), not a cycle button.
export function Topbar({ onSearch, onPreferences }: { onSearch: () => void; onPreferences: () => void }) {
  const { principal } = useSession()

  return (
    <header className="app__topbar">
      <div className="topbar-row">
        <a className="topbar__logo" href="/" aria-label="Verity — Home">
          <img className="wordmark wordmark--light" src="/assets/verity-wordmark-dark.png" alt="Verity" width={74} height={22} />
          <img className="wordmark wordmark--dark" src="/assets/verity-wordmark-white.png" alt="" aria-hidden="true" width={74} height={22} />
        </a>
        <nav className="breadcrumb" aria-label="Breadcrumb">
          <span className="breadcrumb__item breadcrumb__item--current">Home</span>
        </nav>
        <span className="l-spacer" />
        <div className="topbar__utils">
          <div
            className="search-field"
            role="button"
            tabIndex={0}
            onClick={onSearch}
            onKeyDown={(e) => (e.key === 'Enter' || e.key === ' ') && onSearch()}
            aria-label="Open search"
          >
            <svg className="icon" aria-hidden="true"><use href="#i-search" /></svg>
            <input readOnly tabIndex={-1} aria-hidden="true" placeholder="Search…" />
            <kbd>⌘J</kbd>
          </div>
          <button className="btn btn--icon btn--ghost" aria-label="Help" title="Help (Ctrl+Shift+?)" onClick={() => helpDrawer.open('home')}>
            <svg className="icon" aria-hidden="true"><use href="#i-help" /></svg>
          </button>
          {principal && <AccountMenu principal={principal} onPreferences={onPreferences} />}
        </div>
      </div>
    </header>
  )
}
