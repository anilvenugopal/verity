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

export function AgentDetail() {
  const { id } = useParams<{ id: string }>()
  const navigate = useNavigate()
  const [agent, setAgent] = useState<Executable | null>(null)
  const [versions, setVersions] = useState<ExecutableVersion[] | null>(null)
  const [champion, setChampion] = useState<ExecutableVersion | null>(null)
  const [championChecked, setChampionChecked] = useState(false)

  useEffect(() => {
    if (!id) return
    api.get<Executable>(`/api/executables/${id}`).then(setAgent).catch(() => setAgent(null))
    api.get<ExecutableVersion[]>(`/api/executables/${id}/versions`).then(setVersions).catch(() => setVersions([]))
    api.get<ExecutableVersion>(`/api/executables/${id}/champion`)
      .then((c) => { setChampion(c); setChampionChecked(true) })
      .catch(() => setChampionChecked(true))
  }, [id])

  // Transparent redirect: once champion check and version list have both settled,
  // navigate to the best version so the user lands directly on version detail.
  useEffect(() => {
    if (!championChecked || versions === null || !id) return
    const target = champion ?? bestVersion(versions)
    if (target) navigate(`/registry/agents/${id}/versions/${target.executable_version_id}`, { replace: true })
  }, [championChecked, versions, champion, id, navigate])

  if (!id) return null
  if (agent === null) return <div className="canvas-pad"><span className="input-hint">Loading…</span></div>

  // Fallback render when there are no versions (redirect never fires)
  const openVersion = (vid: string) => navigate(`/registry/agents/${id}/versions/${vid}`)
  const onKey = (vid: string) => (e: KeyboardEvent) => (e.key === 'Enter' || e.key === ' ') && openVersion(vid)

  return (
    <div className="canvas-pad">
      <div className="page-head">
        <div>
          <div className="page-head__eyebrow"><Link to="/registry/agents">Agents</Link></div>
          <div className="page-head__title">{agent.name}</div>
          <div className="page-head__badges">
            <span className="chip chip--static">agent</span>
            {agent.champion_semver && (
              <span className="badge badge--champion">
                <span className="badge__dot" />
                <span className="badge__label">champion {agent.champion_semver}</span>
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
              <p className="empty-state__body">Create a version to begin composing this agent.</p>
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
              const isChampion = agent.champion_semver != null && v.semver === agent.champion_semver
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
                  <span className="reg-entity-desc" />
                </div>
              )
            })}
          </div>
        )}
      </section>
    </div>
  )
}
