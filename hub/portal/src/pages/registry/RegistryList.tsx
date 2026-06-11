import { type FormEvent, Fragment, useEffect, useState } from 'react'
import { api, ApiException } from '@/api/client'
import { useSession } from '@/auth/useSession'
import { useToast } from '@/shell/useToast'
import type { Executable, ExecutableVersion } from '@/api/types'

// Minimal registry (003 US2): create governed assets (agents/tasks) + versions, advance the
// lifecycle, and see the PROMOTION GATE in action — advancing to a production stage (challenger/
// champion) is blocked unless the asset is linked to an approved intake with resolved obligations.
const LADDER = ['draft', 'candidate', 'staging', 'challenger', 'champion', 'deprecated']
const nextStage = (s: string | null) => {
  const i = LADDER.indexOf(s ?? 'draft')
  return i >= 0 && i < LADDER.length - 1 ? LADDER[i + 1] : null
}

export function RegistryList() {
  const { canDo } = useSession()
  const [exes, setExes] = useState<Executable[]>([])
  const [sel, setSel] = useState<string | null>(null)
  const [versions, setVersions] = useState<ExecutableVersion[]>([])
  const [name, setName] = useState('')
  const [kind, setKind] = useState('task')
  const [msg, setMsg] = useState('')
  const [busy, setBusy] = useState(false)

  const { success } = useToast()
  const canAuthor = canDo('author_registry')
  const canPromote = canDo('promote_registry')

  const loadExes = () => api.get<Executable[]>('/api/executables').then(setExes).catch(() => setExes([]))
  const loadVersions = (id: string) => api.get<ExecutableVersion[]>(`/api/executables/${id}/versions`).then(setVersions).catch(() => setVersions([]))
  useEffect(() => { loadExes() }, [])
  useEffect(() => { if (sel) loadVersions(sel) }, [sel])

  async function createExe(e: FormEvent) {
    e.preventDefault()
    if (busy) return
    setBusy(true); setMsg('')
    try { const ex = await api.post<Executable>('/api/executables', { name, kind_code: kind }); setName(''); success('Asset created'); loadExes(); setSel(ex.executable_id) }
    catch (err) { setMsg(err instanceof ApiException ? err.body.detail : 'Could not create asset.') }
    finally { setBusy(false) }
  }
  async function addVersion() {
    if (!sel || busy) return
    setBusy(true)
    try { await api.post(`/api/executables/${sel}/versions`); success('Version created'); loadVersions(sel); loadExes() } finally { setBusy(false) }
  }
  async function advance(vid: string, to: string) {
    if (busy) return
    setBusy(true); setMsg('')
    try { await api.post(`/api/versions/${vid}/lifecycle`, { to_stage: to }); if (sel) loadVersions(sel); setMsg(''); success('Stage advanced') }
    catch (err) { setMsg(err instanceof ApiException ? err.body.detail : 'Advance failed.') }
    finally { setBusy(false) }
  }

  return (
    <div className="canvas-pad">
      <div className="page-head"><div>
        <div className="page-head__title">Registry</div>
        <div className="page-head__sub">Governed AI assets (agents &amp; tasks). Promotion to a production stage is gated on an approved intake with resolved obligations.</div>
      </div></div>

      <div className="card">
        <div className="rail-panel__title">Assets</div>
        {canAuthor && (
          <form className="l-cluster" onSubmit={createExe}>
            <input className="input" placeholder="Asset name" value={name} onChange={(e) => setName(e.target.value)} required />
            <select className="input" value={kind} onChange={(e) => setKind(e.target.value)}><option value="task">task</option><option value="agent">agent</option></select>
            <button className="btn btn--secondary btn--md" disabled={busy || !name}>Create asset</button>
          </form>
        )}
        <div className="kv">
          {exes.map((x) => (
            <Fragment key={x.executable_id}>
              <span className="kv__k"><button className={`btn btn--sm ${sel === x.executable_id ? 'btn--secondary' : 'btn--ghost'}`} onClick={() => setSel(x.executable_id)}>{x.name}</button></span>
              <span className="kv__v"><span className="chip chip--static">{x.kind_code}</span> <span className="u-text-tertiary">{x.version_count} version(s)</span></span>
            </Fragment>
          ))}
          {exes.length === 0 && <span className="input-hint">No assets yet.</span>}
        </div>
      </div>

      {sel && (
        <div className="card">
          <div className="rail-panel__title">Versions</div>
          {canAuthor && <div className="l-cluster"><button className="btn btn--secondary btn--sm" disabled={busy} onClick={addVersion}>+ New version</button></div>}
          {msg && <p className="input-hint">{msg}</p>}
          <div className="kv">
            {versions.map((v) => {
              const n = nextStage(v.lifecycle_stage)
              return (
                <Fragment key={v.executable_version_id}>
                  <span className="kv__k">{v.semver}<div className="u-text-tertiary"><span className="chip chip--static">{v.lifecycle_stage}</span></div></span>
                  <span className="kv__v">
                    {canPromote && n ? <button className="btn btn--ghost btn--sm" disabled={busy} onClick={() => advance(v.executable_version_id, n)}>Advance to {n}</button> : <span className="u-text-tertiary">{n ? '' : 'terminal'}</span>}
                  </span>
                </Fragment>
              )
            })}
            {versions.length === 0 && <span className="input-hint">No versions — create one to start.</span>}
          </div>
        </div>
      )}
    </div>
  )
}
