import { useEffect, useState } from 'react'
import { Link, useParams } from 'react-router-dom'
import { api } from '@/api/client'
import type { ToolSummary, ToolVersionDetail as ToolVersionDetailType, ToolVersionSummary, UsedByEntry } from '@/api/types'
import { VersionSwitcher, type VersionEntry } from '@/components/VersionSwitcher'
import '../RegistryDetail.css'
import '../RegistryLists.css'

export function ToolVersionDetail() {
  const { id, vid } = useParams<{ id: string; vid: string }>()
  const [tool, setTool] = useState<ToolSummary | null>(null)
  const [versions, setVersions] = useState<ToolVersionSummary[]>([])
  const [detail, setDetail] = useState<ToolVersionDetailType | null>(null)
  const [usedBy, setUsedBy] = useState<UsedByEntry[] | null>(null)

  useEffect(() => {
    if (!id) return
    api.get<ToolSummary>(`/api/tools/${id}`).then(setTool).catch(() => {})
    api.get<ToolVersionSummary[]>(`/api/tools/${id}/versions`).then(setVersions).catch(() => {})
  }, [id])

  useEffect(() => {
    if (!vid) return
    setDetail(null)
    setUsedBy(null)
    api.get<ToolVersionDetailType>(`/api/tool-versions/${vid}`).then(setDetail).catch(() => setDetail(null))
    api.get<UsedByEntry[]>(`/api/tool-versions/${vid}/used-by`).then(setUsedBy).catch(() => setUsedBy([]))
  }, [vid])

  if (!id || !vid) return null
  if (!tool && !detail) return <div className="canvas-pad"><span className="input-hint">Loading…</span></div>

  const versionEntries: VersionEntry[] = versions.map((v) => ({
    id: v.tool_version_id,
    semver: v.semver,
    hint: v.data_classification_code ?? undefined,
  }))

  return (
    <div className="canvas-pad">
      <div className="page-head">
        <div>
          <div className="page-head__eyebrow">
            <Link to="/registry/tools">Tools</Link>
          </div>
          <div className="page-head__title">{tool?.display_name ?? tool?.name ?? '…'}</div>
          {tool?.description && <div className="page-head__sub">{tool.description}</div>}
          <div className="page-head__badges">
            <VersionSwitcher
              versions={versionEntries}
              currentId={vid}
              getTo={(v) => `/registry/tools/${id}/versions/${v}`}
            />
            {tool?.name && <span className="chip chip--code">{tool.name}</span>}
            {tool?.application_code && <span className="chip chip--app">{tool.application_code}</span>}
            {tool?.transport_code && <span className="chip chip--static">{tool.transport_code.replace(/_/g, ' ')}</span>}
            {tool?.is_write_operation && <span className="chip chip--warn">Write</span>}
            {detail?.data_classification_code && (
              <span className="chip chip--static">{detail.data_classification_code.replace(/_/g, ' ')}</span>
            )}
          </div>
        </div>
      </div>

      <section className="section">
        <div className="section__head"><span className="eyebrow">Input schema</span></div>
        {!detail ? (
          <p className="input-hint">Loading…</p>
        ) : !detail.input_schema ? (
          <p className="input-hint">No input schema defined for this version.</p>
        ) : (
          <pre className="code-block">{JSON.stringify(detail.input_schema, null, 2)}</pre>
        )}
      </section>

      <section className="section">
        <div className="section__head"><span className="eyebrow">Used by</span></div>
        <div className="log-table">
          {usedBy === null ? (
            <div className="empty-state"><div className="empty-state__body">Loading…</div></div>
          ) : usedBy.length === 0 ? (
            <div className="empty-state"><div className="empty-state__body">Not used by any executable versions.</div></div>
          ) : (
            <>
              <div className="log-table__header used-by-grid">
                <span className="eyebrow">Executable</span>
                <span className="eyebrow">Kind</span>
                <span className="eyebrow">Version</span>
              </div>
              {usedBy.map((u) => (
                <div key={u.executable_version_id} className="log-row used-by-grid">
                  <Link to={`/registry/${u.kind_code === 'agent' ? 'agents' : 'tasks'}/${u.executable_id}`}
                        className="reg-row-primary">
                    {u.executable_name}
                  </Link>
                  <span className="chip chip--static">{u.kind_code}</span>
                  <span className="reg-entity-desc">{u.semver}</span>
                </div>
              ))}
            </>
          )}
        </div>
      </section>
    </div>
  )
}
