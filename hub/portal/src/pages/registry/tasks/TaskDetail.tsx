import { type KeyboardEvent, useEffect, useState } from 'react'
import { Link, useNavigate, useParams } from 'react-router-dom'
import { api } from '@/api/client'
import type { Executable, ExecutableVersion } from '@/api/types'
import '../RegistryDetail.css'
import '../RegistryLists.css'

const STAGE_ORDER: Record<string, number> = {
  champion: 5, certified: 4, approved: 3, review: 2, draft: 1, deprecated: 0,
}

function parseSemver(s: string | null | undefined): [number, number, number] {
  if (!s) return [0, 0, 0]
  const p = s.split('.').map(Number)
  return [p[0] ?? 0, p[1] ?? 0, p[2] ?? 0]
}

function bestVersion(versions: ExecutableVersion[]): ExecutableVersion | null {
  if (versions.length === 0) return null
  return [...versions].sort((a, b) => {
    const sa = STAGE_ORDER[a.lifecycle_stage ?? ''] ?? -1
    const sb = STAGE_ORDER[b.lifecycle_stage ?? ''] ?? -1
    if (sb !== sa) return sb - sa
    const [am, an, ap] = parseSemver(a.semver)
    const [bm, bn, bp] = parseSemver(b.semver)
    return bm - am || bn - an || bp - ap
  })[0] ?? null
}

function stageBadge(stage: string | null | undefined) {
  const s = stage ?? 'draft'
  return <span className={`badge badge--${s}`}><span className="badge__dot" /><span className="badge__label">{s}</span></span>
}

export function TaskDetail() {
  const { id } = useParams<{ id: string }>()
  const navigate = useNavigate()
  const [task, setTask] = useState<Executable | null>(null)
  const [versions, setVersions] = useState<ExecutableVersion[] | null>(null)
  const [champion, setChampion] = useState<ExecutableVersion | null>(null)
  const [championChecked, setChampionChecked] = useState(false)

  useEffect(() => {
    if (!id) return
    api.get<Executable>(`/api/executables/${id}`).then(setTask).catch(() => setTask(null))
    api.get<ExecutableVersion[]>(`/api/executables/${id}/versions`).then(setVersions).catch(() => setVersions([]))
    api.get<ExecutableVersion>(`/api/executables/${id}/champion`)
      .then((c) => { setChampion(c); setChampionChecked(true) })
      .catch(() => setChampionChecked(true))
  }, [id])

  useEffect(() => {
    if (!championChecked || versions === null || !id) return
    const target = champion ?? bestVersion(versions)
    if (target) navigate(`/registry/tasks/${id}/versions/${target.executable_version_id}`, { replace: true })
  }, [championChecked, versions, champion, id, navigate])

  if (!id) return null
  if (task === null) return <div className="canvas-pad"><span className="input-hint">Loading…</span></div>

  const openVersion = (vid: string) => navigate(`/registry/tasks/${id}/versions/${vid}`)
  const onKey = (vid: string) => (e: KeyboardEvent) => (e.key === 'Enter' || e.key === ' ') && openVersion(vid)

  return (
    <div className="canvas-pad">
      <div className="page-head">
        <div>
          <div className="page-head__eyebrow"><Link to="/registry/tasks">Tasks</Link></div>
          <div className="page-head__title">{task.name}</div>
          <div className="page-head__badges">
            <span className="chip chip--static">task</span>
            {task.champion_semver && (
              <span className="badge badge--champion">
                <span className="badge__dot" />
                <span className="badge__label">champion {task.champion_semver}</span>
              </span>
            )}
          </div>
        </div>
      </div>

      <section className="section">
        <div className="section__head">
          <span className="eyebrow">Version history</span>
          <span className="reg-count" style={{ marginLeft: 'auto' }}>
            {versions === null ? '' : `${versions.length} version${versions.length !== 1 ? 's' : ''}`}
          </span>
        </div>
        {versions === null ? (
          <div className="log-table"><div className="empty-state"><div className="empty-state__body">Loading…</div></div></div>
        ) : versions.length === 0 ? (
          <div className="log-table">
            <div className="empty-state">
              <div className="empty-state__title">No versions yet</div>
              <p className="empty-state__body">Create a version to begin composing this task.</p>
            </div>
          </div>
        ) : (
          <div className="log-table">
            <div className="log-table__header version-grid">
              <span className="eyebrow">Semver</span>
              <span className="eyebrow">Stage</span>
              <span className="eyebrow">Tier</span>
              <span className="eyebrow">Capability</span>
              <span className="eyebrow" />
            </div>
            {versions.map((v) => {
              const isChampion = task.champion_semver != null && v.semver === task.champion_semver
              return (
                <div key={v.executable_version_id} className="log-row version-grid"
                     role="button" tabIndex={0}
                     onClick={() => openVersion(v.executable_version_id)}
                     onKeyDown={onKey(v.executable_version_id)}>
                  <div className="reg-entity-cell">
                    <span className="reg-entity-name">{v.semver ?? '—'}</span>
                  </div>
                  <div style={{ display: 'flex', gap: 'var(--space-1)', alignItems: 'center' }}>
                    {stageBadge(v.lifecycle_stage)}
                    {isChampion && <span className="badge badge--champion"><span className="badge__dot" /></span>}
                  </div>
                  <span className="reg-entity-desc">{v.governance_tier_code ?? '—'}</span>
                  <span className="reg-entity-desc">{v.capability_type_code ?? '—'}</span>
                  <span />
                </div>
              )
            })}
          </div>
        )}
      </section>
    </div>
  )
}
