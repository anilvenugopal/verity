import { useEffect, useState } from 'react'
import { Link, useNavigate, useParams } from 'react-router-dom'
import { api } from '@/api/client'
import type { ToolSummary, ToolVersionSummary } from '@/api/types'
import '../RegistryDetail.css'
import '../RegistryLists.css'

function parseSemver(s: string | null | undefined): [number, number, number] {
  if (!s) return [0, 0, 0]
  const p = s.split('.').map(Number)
  return [p[0] ?? 0, p[1] ?? 0, p[2] ?? 0]
}

function bestToolVersion(versions: ToolVersionSummary[]): ToolVersionSummary | null {
  if (versions.length === 0) return null
  return [...versions].sort((a, b) => {
    const [am, an, ap] = parseSemver(a.semver)
    const [bm, bn, bp] = parseSemver(b.semver)
    return bm - am || bn - an || bp - ap
  })[0] ?? null
}

export function ToolDetail() {
  const { id } = useParams<{ id: string }>()
  const navigate = useNavigate()
  const [tool, setTool] = useState<ToolSummary | null>(null)
  const [versions, setVersions] = useState<ToolVersionSummary[] | null>(null)

  useEffect(() => {
    if (!id) return
    api.get<ToolSummary>(`/api/tools/${id}`).then(setTool).catch(() => setTool(null))
    api.get<ToolVersionSummary[]>(`/api/tools/${id}/versions`).then(setVersions).catch(() => setVersions([]))
  }, [id])

  useEffect(() => {
    if (versions === null || !id) return
    const target = bestToolVersion(versions)
    if (target) navigate(`/registry/tools/${id}/versions/${target.tool_version_id}`, { replace: true })
  }, [versions, id, navigate])

  if (!id) return null
  if (tool === null) return <div className="canvas-pad"><span className="input-hint">Loading…</span></div>

  // Fallback: shown only when there are no versions (redirect never fires)
  return (
    <div className="canvas-pad">
      <div className="page-head">
        <div>
          <div className="page-head__eyebrow"><Link to="/registry/tools">Tools</Link></div>
          <div className="page-head__title">{tool.name}</div>
          <div className="page-head__badges">
            <span className="chip chip--static">{tool.transport_code.replace(/_/g, ' ')}</span>
            {tool.is_write_operation && <span className="chip--write">Write</span>}
          </div>
        </div>
      </div>
      <section className="section">
        <div className="log-table">
          <div className="empty-state">
            <div className="empty-state__title">No versions yet</div>
            <p className="empty-state__body">Create a version to define this tool's input schema.</p>
          </div>
        </div>
      </section>
    </div>
  )
}
