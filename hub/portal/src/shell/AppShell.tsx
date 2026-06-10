import { useEffect, useState } from 'react'
import { Outlet } from 'react-router-dom'
import { usePreferences } from '@/hooks/usePreferences'
import { Topbar } from './Topbar'
import { Rail } from './Rail'
import { Sidebar } from './Sidebar'
import { AppLauncher } from './AppLauncher'
import { CommandPalette } from './CommandPalette'
import { PreferencesModal } from './PreferencesModal'
import './AppShell.css'

// The five-region app shell (FR-009): topbar · body(rail + canvas) · statusbar. The sidebar region
// is contextual and only rendered when an app contributes nav children (none on Home — matches
// sample.html). The route's page renders into the canvas via <Outlet />.
export function AppShell() {
  const [launcherOpen, setLauncherOpen] = useState(false)
  const [paletteOpen, setPaletteOpen] = useState(false)
  const [prefsOpen, setPrefsOpen] = useState(false)
  const [sidebarCollapsed, setSidebarCollapsed] = useState(false)
  const { prefs, update } = usePreferences()

  // ⌘J / Ctrl-J opens the global search (command palette). The rail launcher is the apps grid.
  // ⌘, opens preferences (standard macOS convention).
  useEffect(() => {
    const onKey = (e: KeyboardEvent) => {
      if ((e.metaKey || e.ctrlKey) && e.key.toLowerCase() === 'j') {
        e.preventDefault()
        setPaletteOpen(true)
      }
      if ((e.metaKey || e.ctrlKey) && e.key === ',') {
        e.preventDefault()
        setPrefsOpen(true)
      }
    }
    document.addEventListener('keydown', onKey)
    return () => document.removeEventListener('keydown', onKey)
  }, [])

  return (
    <div className="app">
      <Topbar onSearch={() => setPaletteOpen(true)} onPreferences={() => setPrefsOpen(true)} />
      <div className="app__body">
        <Rail
          onLauncher={() => setLauncherOpen(true)}
          sidebarCollapsed={sidebarCollapsed}
          onToggleSidebar={() => setSidebarCollapsed(c => !c)}
        />
        <Sidebar collapsed={sidebarCollapsed} onCollapse={() => setSidebarCollapsed(true)} />
        <main className="app__canvas">
          <Outlet />
        </main>
      </div>
      <footer className="app__statusbar">
        <div className="statusbar-row">
          <span className="l-cluster"><span className="badge__dot" />Connected · live updates</span>
          <span className="l-spacer" />
          <span className="u-mono">v2.0.0-dev</span>
        </div>
      </footer>
      {launcherOpen && <AppLauncher onClose={() => setLauncherOpen(false)} />}
      {paletteOpen && <CommandPalette onClose={() => setPaletteOpen(false)} />}
      {prefsOpen && <PreferencesModal prefs={prefs} onUpdate={update} onClose={() => setPrefsOpen(false)} />}
    </div>
  )
}
