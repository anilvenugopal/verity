import { useCallback, useEffect, useState } from 'react'
import { api } from '@/api/client'
import type { UserPreferences } from '@/api/types'

const DEFAULTS: UserPreferences = { theme_mode: 'system', theme_palette: 'gray' }

export function applyTheme(prefs: UserPreferences): void {
  const root = document.documentElement
  const prefersDark = window.matchMedia('(prefers-color-scheme: dark)').matches
  const dark = prefs.theme_mode === 'dark' || (prefs.theme_mode === 'system' && prefersDark)
  root.classList.toggle('dark', dark)
  if (prefs.theme_palette === 'gray') delete root.dataset.theme
  else root.dataset.theme = prefs.theme_palette
}

export function usePreferences() {
  const [prefs, setPrefs] = useState<UserPreferences>(DEFAULTS)

  useEffect(() => {
    api.get<UserPreferences>('/api/preferences')
      .then((p) => { setPrefs(p); applyTheme(p) })
      .catch(() => { /* non-fatal: use client defaults */ })
  }, [])

  // Re-apply when OS dark-mode changes and mode is set to "system"
  useEffect(() => {
    if (prefs.theme_mode !== 'system') return
    const mq = window.matchMedia('(prefers-color-scheme: dark)')
    const onchange = () => applyTheme(prefs)
    mq.addEventListener('change', onchange)
    return () => mq.removeEventListener('change', onchange)
  }, [prefs])

  const update = useCallback(async (changes: Partial<UserPreferences>): Promise<void> => {
    const next = { ...prefs, ...changes }
    setPrefs(next)
    applyTheme(next)
    // Fire-and-forget persist — keep the applied state regardless of backend outcome.
    // If the backend is unreachable the preference holds for this session but won't
    // survive a reload until the migration is applied and the server is reachable.
    api.patch<UserPreferences>('/api/preferences', changes)
      .then((saved) => { setPrefs(saved); applyTheme(saved) })
      .catch(() => { /* non-fatal: session preference stays, just won't be persisted */ })
  }, [prefs])

  return { prefs, update }
}
