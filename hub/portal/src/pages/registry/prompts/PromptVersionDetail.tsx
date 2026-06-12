import { useEffect, useState } from 'react'
import { Link, useParams } from 'react-router-dom'
import { api } from '@/api/client'
import type { PromptSummary, PromptVersionDetail as PromptVersionDetailType, PromptVersionSummary, UsedByEntry } from '@/api/types'
import { VersionSwitcher, type VersionEntry } from '@/components/VersionSwitcher'
import '../RegistryDetail.css'
import '../RegistryLists.css'

export function PromptVersionDetail() {
  const { id, vid } = useParams<{ id: string; vid: string }>()
  const [prompt, setPrompt] = useState<PromptSummary | null>(null)
  const [versions, setVersions] = useState<PromptVersionSummary[]>([])
  const [detail, setDetail] = useState<PromptVersionDetailType | null>(null)
  const [usedBy, setUsedBy] = useState<UsedByEntry[] | null>(null)

  useEffect(() => {
    if (!id) return
    api.get<PromptSummary>(`/api/prompts/${id}`).then(setPrompt).catch(() => {})
    api.get<PromptVersionSummary[]>(`/api/prompts/${id}/versions`).then(setVersions).catch(() => {})
  }, [id])

  useEffect(() => {
    if (!vid) return
    setDetail(null)
    setUsedBy(null)
    api.get<PromptVersionDetailType>(`/api/prompt-versions/${vid}`).then(setDetail).catch(() => setDetail(null))
    api.get<UsedByEntry[]>(`/api/prompt-versions/${vid}/used-by`).then(setUsedBy).catch(() => setUsedBy([]))
  }, [vid])

  if (!id || !vid) return null
  if (!prompt && !detail) return <div className="canvas-pad"><span className="input-hint">Loading…</span></div>

  const versionEntries: VersionEntry[] = versions.map((v) => ({
    id: v.prompt_version_id,
    semver: v.semver,
    hint: v.content_hash.slice(0, 8),
  }))

  const textBlocks = detail?.blocks?.filter((b) => b.text != null) ?? []

  return (
    <div className="canvas-pad">
      <div className="page-head">
        <div>
          <div className="page-head__eyebrow">
            <Link to="/registry/prompts">Prompts</Link>
          </div>
          <div className="page-head__title">{prompt?.display_name ?? prompt?.name ?? '…'}</div>
          {prompt?.description && <div className="page-head__sub">{prompt.description}</div>}
          <div className="page-head__badges">
            <VersionSwitcher
              versions={versionEntries}
              currentId={vid}
              getTo={(v) => `/registry/prompts/${id}/versions/${v}`}
            />
            {prompt?.name && <span className="chip chip--code">{prompt.name}</span>}
            {prompt?.application_code && <span className="chip chip--app">{prompt.application_code}</span>}
          </div>
        </div>
      </div>

      <section className="section">
        <div className="section__head"><span className="eyebrow">Content</span></div>
        {!detail ? (
          <p className="input-hint">Loading…</p>
        ) : textBlocks.length === 0 ? (
          <p className="input-hint">No text blocks.</p>
        ) : (
          textBlocks.map((b, i) => (
            <pre key={i} className="code-block" style={{ marginBottom: i < textBlocks.length - 1 ? 'var(--space-2)' : 0 }}>
              {String(b.text ?? '')}
            </pre>
          ))
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
