import { useEffect, useState } from 'react'
import { Link, useNavigate, useParams } from 'react-router-dom'
import { api } from '@/api/client'
import type { PromptSummary, PromptVersionSummary } from '@/api/types'
import '../RegistryDetail.css'
import '../RegistryLists.css'

function parseSemver(s: string | null | undefined): [number, number, number] {
  if (!s) return [0, 0, 0]
  const p = s.split('.').map(Number)
  return [p[0] ?? 0, p[1] ?? 0, p[2] ?? 0]
}

function bestPromptVersion(versions: PromptVersionSummary[]): PromptVersionSummary | null {
  if (versions.length === 0) return null
  return [...versions].sort((a, b) => {
    const [am, an, ap] = parseSemver(a.semver)
    const [bm, bn, bp] = parseSemver(b.semver)
    return bm - am || bn - an || bp - ap
  })[0] ?? null
}

export function PromptDetail() {
  const { id } = useParams<{ id: string }>()
  const navigate = useNavigate()
  const [prompt, setPrompt] = useState<PromptSummary | null>(null)
  const [versions, setVersions] = useState<PromptVersionSummary[] | null>(null)

  useEffect(() => {
    if (!id) return
    api.get<PromptSummary>(`/api/prompts/${id}`).then(setPrompt).catch(() => setPrompt(null))
    api.get<PromptVersionSummary[]>(`/api/prompts/${id}/versions`).then(setVersions).catch(() => setVersions([]))
  }, [id])

  useEffect(() => {
    if (versions === null || !id) return
    const target = bestPromptVersion(versions)
    if (target) navigate(`/registry/prompts/${id}/versions/${target.prompt_version_id}`, { replace: true })
  }, [versions, id, navigate])

  if (!id) return null
  if (prompt === null) return <div className="canvas-pad"><span className="input-hint">Loading…</span></div>

  // Fallback: shown only when there are no versions (redirect never fires)
  return (
    <div className="canvas-pad">
      <div className="page-head">
        <div>
          <div className="page-head__eyebrow"><Link to="/registry/prompts">Prompts</Link></div>
          <div className="page-head__title">{prompt.name}</div>
        </div>
      </div>
      <section className="section">
        <div className="log-table">
          <div className="empty-state">
            <div className="empty-state__title">No versions yet</div>
            <p className="empty-state__body">Create a version to add prompt content.</p>
          </div>
        </div>
      </section>
    </div>
  )
}
