import { useCallback, useEffect, useState } from 'react'
import { api } from '@/api/client'
import type { UserPreferences } from '@/api/types'

const DEFAULTS: UserPreferences = { theme_mode: 'system', theme_palette: 'gray' }
const STORAGE_KEY = 'verity:prefs'

function readCache(): UserPreferences | null {
  try {
    const raw = localStorage.getItem(STORAGE_KEY)
    return raw ? (JSON.parse(raw) as UserPreferences) : null
  } catch { return null }
}

function writeCache(prefs: UserPreferences): void {
  try { localStorage.setItem(STORAGE_KEY, JSON.stringify(prefs)) } catch { /* storage full/private */ }
}

export function applyTheme(prefs: UserPreferences): void {
  const root = document.documentElement
  const prefersDark = window.matchMedia('(prefers-color-scheme: dark)').matches
  const dark = prefs.theme_mode === 'dark' || (prefs.theme_mode === 'system' && prefersDark)
  root.classList.toggle('dark', dark)
  if (prefs.theme_palette === 'gray') delete root.dataset.theme
  else root.dataset.theme = prefs.theme_palette
}

export function usePreferences() {
  const [prefs, setPrefs] = useState<UserPreferences>(() => readCache() ?? DEFAULTS)

  useEffect(() => {
    api.get<UserPreferences>('/api/preferences')
      .then((p) => { setPrefs(p); applyTheme(p); writeCache(p) })
      .catch(() => { /* non-fatal: cached/default preference stays */ })
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
      .then((saved) => { setPrefs(saved); applyTheme(saved); writeCache(saved) })
      .catch(() => { /* non-fatal: session preference stays, just won't be persisted */ })
  }, [prefs])

  return { prefs, update }
}
