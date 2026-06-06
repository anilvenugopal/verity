import { useState } from 'react'
import { useSession } from '@/auth/useSession'
import { AccountMenu } from './AccountMenu'

// The kit's themes: data-theme family (Gray=default / slate / warm) × .dark. One control cycles all.
const THEMES = [
  { theme: '', dark: false, label: 'Gray · Light' },
  { theme: '', dark: true, label: 'Gray · Dark' },
  { theme: 'slate', dark: false, label: 'Slate · Light' },
  { theme: 'slate', dark: true, label: 'Slate · Dark' },
  { theme: 'warm', dark: false, label: 'Warm · Light' },
  { theme: 'warm', dark: true, label: 'Warm · Dark' },
]

function applyTheme(t: { theme: string; dark: boolean }) {
  const root = document.documentElement
  if (t.theme) root.dataset.theme = t.theme
  else delete root.dataset.theme
  root.classList.toggle('dark', t.dark)
}

function currentThemeIndex(): number {
  const root = document.documentElement
  const dark = root.classList.contains('dark')
  const theme = root.dataset.theme ?? ''
  const i = THEMES.findIndex((t) => t.theme === theme && t.dark === dark)
  return i >= 0 ? i : 0
}

// Topbar: wordmark · breadcrumb · spacer · utils (search, theme, help, account menu). Reuses
// canonical topbar__logo / breadcrumb / topbar__utils / btn / search-field; row layout is page-local.
export function Topbar({ onSearch }: { onSearch: () => void }) {
  const { principal } = useSession()
  const [themeIdx, setThemeIdx] = useState(currentThemeIndex)

  function cycleTheme() {
    const next = (themeIdx + 1) % THEMES.length
    applyTheme(THEMES[next])
    setThemeIdx(next)
  }

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
          <button
            className="btn btn--icon btn--ghost"
            onClick={cycleTheme}
            aria-label={`Theme: ${THEMES[themeIdx].label} — click to cycle`}
            title={`Theme: ${THEMES[themeIdx].label}`}
          >
            <svg className="icon" aria-hidden="true"><use href="#i-theme" /></svg>
          </button>
          <button className="btn btn--icon btn--ghost" aria-label="Help">
            <svg className="icon" aria-hidden="true"><use href="#i-help" /></svg>
          </button>
          {principal && <AccountMenu principal={principal} />}
        </div>
      </div>
    </header>
  )
}
