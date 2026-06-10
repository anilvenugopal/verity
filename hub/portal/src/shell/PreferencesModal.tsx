import { useEffect, useState } from 'react'
import type { UserPreferences } from '@/api/types'
import './PreferencesModal.css'

type Category =
  | 'appearance'
  | 'notifications'
  | 'lists'
  | 'workflow'
  | 'evaluation'
  | 'accessibility'
  | 'shortcuts'

const CATEGORIES: { key: Category; label: string; icon: string; live: boolean }[] = [
  { key: 'appearance',    label: 'Appearance',         icon: 'i-theme',         live: true  },
  { key: 'notifications', label: 'Notifications',      icon: 'i-notifications', live: false },
  { key: 'lists',         label: 'Lists & Views',      icon: 'i-filter',        live: false },
  { key: 'workflow',      label: 'Workflow',            icon: 'i-app-intake',    live: false },
  { key: 'evaluation',    label: 'Evaluation Display', icon: 'i-metric-score',  live: false },
  { key: 'accessibility', label: 'Accessibility',       icon: 'i-help',          live: false },
  { key: 'shortcuts',     label: 'Keyboard Shortcuts', icon: 'i-command',       live: false },
]

interface Props {
  prefs: UserPreferences
  onUpdate: (changes: Partial<UserPreferences>) => void
  onClose: () => void
}

export function PreferencesModal({ prefs, onUpdate, onClose }: Props) {
  const [category, setCategory] = useState<Category>('appearance')

  useEffect(() => {
    const onKey = (e: KeyboardEvent) => { if (e.key === 'Escape') onClose() }
    document.addEventListener('keydown', onKey)
    return () => document.removeEventListener('keydown', onKey)
  }, [onClose])

  const active = CATEGORIES.find((c) => c.key === category)!

  return (
    <div className="overlay overlay--prefs" onClick={onClose}>
      <div
        className="modal modal--prefs"
        role="dialog"
        aria-modal="true"
        aria-label="Preferences"
        onClick={(e) => e.stopPropagation()}
      >
        <div className="prefs__header">
          <span className="prefs__title">Preferences</span>
          <button className="sidebar__toggle" onClick={onClose} aria-label="Close preferences">
            <svg className="icon" aria-hidden="true"><use href="#i-clear" /></svg>
          </button>
        </div>

        <div className="prefs__body">
          <nav className="prefs__nav" aria-label="Preference categories">
            {CATEGORIES.map((c) => (
              <button
                key={c.key}
                className={`prefs__nav-item${category === c.key ? ' is-active' : ''}`}
                onClick={() => setCategory(c.key)}
                aria-current={category === c.key ? 'page' : undefined}
              >
                <svg className="icon" aria-hidden="true"><use href={`#${c.icon}`} /></svg>
                <span>{c.label}</span>
                {!c.live && <span className="prefs__soon">Soon</span>}
              </button>
            ))}
          </nav>

          <div className="prefs__panel">
            {category === 'appearance'
              ? <AppearancePanel prefs={prefs} onUpdate={onUpdate} />
              : <ComingSoonPanel icon={active.icon} label={active.label} />
            }
          </div>
        </div>
      </div>
    </div>
  )
}

// ── Appearance ────────────────────────────────────────────────────────────────

function AppearancePanel({ prefs, onUpdate }: { prefs: UserPreferences; onUpdate: (c: Partial<UserPreferences>) => void }) {
  return (
    <div className="prefs__sections">
      <section>
        <h3 className="prefs__section-title">Mode</h3>
        <p className="prefs__section-desc">Choose light, dark, or follow your system setting.</p>
        <div className="theme-picker">
          {(['light', 'dark', 'system'] as const).map((mode) => (
            <button
              key={mode}
              className={`theme-btn${prefs.theme_mode === mode ? ' is-selected' : ''}`}
              onClick={() => onUpdate({ theme_mode: mode })}
            >
              <span className={`theme-btn__swatch theme-btn__swatch--${mode}`} />
              <span className="theme-btn__label">{mode.charAt(0).toUpperCase() + mode.slice(1)}</span>
            </button>
          ))}
        </div>
      </section>

      <section>
        <h3 className="prefs__section-title">Color palette</h3>
        <p className="prefs__section-desc">Accent color used throughout the interface.</p>
        <div className="theme-picker">
          {(['gray', 'slate', 'warm'] as const).map((palette) => (
            <button
              key={palette}
              className={`theme-btn${prefs.theme_palette === palette ? ' is-selected' : ''}`}
              onClick={() => onUpdate({ theme_palette: palette })}
            >
              <span className={`theme-btn__swatch theme-btn__swatch--${palette}`} />
              <span className="theme-btn__label">{palette.charAt(0).toUpperCase() + palette.slice(1)}</span>
            </button>
          ))}
        </div>
      </section>
    </div>
  )
}

// ── Coming soon ───────────────────────────────────────────────────────────────

function ComingSoonPanel({ icon, label }: { icon: string; label: string }) {
  return (
    <div className="prefs__coming-soon">
      <svg className="icon" aria-hidden="true"><use href={`#${icon}`} /></svg>
      <p className="prefs__coming-soon__title">{label}</p>
      <p className="prefs__coming-soon__body">These preferences are coming in a future update.</p>
    </div>
  )
}
