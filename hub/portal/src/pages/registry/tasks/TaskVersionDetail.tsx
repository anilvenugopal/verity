import { type FormEvent, useCallback, useEffect, useState } from 'react'
import { Link, useParams } from 'react-router-dom'
import { api, ApiException } from '@/api/client'
import { fmtTs } from '@/api/format'
import { useSession } from '@/auth/useSession'
import { useToast } from '@/shell/useToast'
import type {
  ExecutableVersion,
  InferenceConfigDetail,
  IntakeLink,
  PromptAssignment,
  PromptVersionDetail,
  SourceBinding,
  TargetBinding,
  ToolAssignment,
  ToolVersionDetail,
} from '@/api/types'
import { VersionSwitcher, type VersionEntry } from '@/components/VersionSwitcher'
import '../RegistryDetail.css'
import '../RegistryLists.css'

function stageBadge(stage: string | null | undefined) {
  const s = stage ?? 'draft'
  return <span className={`badge badge--${s}`}><span className="badge__dot" /><span className="badge__label">{s}</span></span>
}

function EmptyState({ message }: { message: string }) {
  return <div className="empty-state" style={{ padding: 'var(--space-4) 0' }}><div className="empty-state__body">{message}</div></div>
}

export function TaskVersionDetail() {
  const { id, vid } = useParams<{ id: string; vid: string }>()
  const { canDo } = useSession()
  const { success, error } = useToast()
  const canAuthor = canDo('author_registry')
  const canPromote = canDo('promote_registry')

  const [version, setVersion] = useState<ExecutableVersion | null>(null)
  const [task, setTask] = useState<{ name: string; display_name?: string | null; description?: string | null; application_code?: string | null } | null>(null)
  const [intakeLink, setIntakeLink] = useState<IntakeLink | null | undefined>(undefined)
  const [allVersions, setAllVersions] = useState<ExecutableVersion[]>([])
  const [prompts, setPrompts] = useState<PromptAssignment[]>([])
  const [tools, setTools] = useState<ToolAssignment[]>([])
  const [sources, setSources] = useState<SourceBinding[]>([])
  const [targets, setTargets] = useState<TargetBinding[]>([])
  const [inferenceConfig, setInferenceConfig] = useState<InferenceConfigDetail | null>(null)
  const [promptDetails, setPromptDetails] = useState<Record<string, PromptVersionDetail>>({})
  const [toolDetails, setToolDetails] = useState<Record<string, ToolVersionDetail>>({})
  const [promoting, setPromoting] = useState(false)

  const [showPromptForm, setShowPromptForm] = useState(false)
  const [promptVid, setPromptVid] = useState('')
  const [apiRole, setApiRole] = useState('system')
  const [assigning, setAssigning] = useState(false)

  const loadVersion = useCallback(() => {
    if (!vid) return
    api.get<ExecutableVersion>(`/api/versions/${vid}`).then(setVersion).catch(() => setVersion(null))
  }, [vid])

  const loadComposition = useCallback(() => {
    if (!vid) return
    api.get<PromptAssignment[]>(`/api/versions/${vid}/prompt-assignments`).then(setPrompts).catch(() => setPrompts([]))
    api.get<ToolAssignment[]>(`/api/versions/${vid}/tool-assignments`).then(setTools).catch(() => setTools([]))
    api.get<SourceBinding[]>(`/api/versions/${vid}/source-bindings`).then(setSources).catch(() => setSources([]))
    api.get<TargetBinding[]>(`/api/versions/${vid}/target-bindings`).then(setTargets).catch(() => setTargets([]))
  }, [vid])

  useEffect(() => {
    if (!id) return
    api.get<typeof task>(`/api/executables/${id}`).then(setTask).catch(() => {})
    api.get<ExecutableVersion[]>(`/api/executables/${id}/versions`).then(setAllVersions).catch(() => {})
    api.get<IntakeLink>(`/api/executables/${id}/intake-link`).then(setIntakeLink).catch(() => setIntakeLink(null))
  }, [id])

  useEffect(() => {
    loadVersion()
    loadComposition()
  }, [loadVersion, loadComposition])

  useEffect(() => {
    if (prompts.length === 0) return
    const map: Record<string, PromptVersionDetail> = {}
    Promise.all(
      prompts.map((pa) =>
        api.get<PromptVersionDetail>(`/api/prompt-versions/${pa.prompt_version_id}`)
          .then((d) => { map[pa.prompt_version_id] = d })
          .catch(() => {})
      )
    ).then(() => setPromptDetails({ ...map }))
  }, [prompts])

  useEffect(() => {
    if (tools.length === 0) return
    const map: Record<string, ToolVersionDetail> = {}
    Promise.all(
      tools.map((ta) =>
        api.get<ToolVersionDetail>(`/api/tool-versions/${ta.tool_version_id}`)
          .then((d) => { map[ta.tool_version_id] = d })
          .catch(() => {})
      )
    ).then(() => setToolDetails({ ...map }))
  }, [tools])

  useEffect(() => {
    if (version?.inference_config_id) {
      api.get<InferenceConfigDetail>(`/api/inference-configs/${version.inference_config_id}`)
        .then(setInferenceConfig).catch(() => setInferenceConfig(null))
    } else {
      setInferenceConfig(null)
    }
  }, [version?.inference_config_id])

  async function handlePromote() {
    if (!vid || promoting) return
    if (!confirm('Promote this version to champion?')) return
    setPromoting(true)
    try {
      await api.post(`/api/versions/${vid}/promote`, {})
      success('Promoted to champion')
      loadVersion()
    } catch (err) {
      error(err instanceof ApiException ? err.body.detail : 'Promotion failed')
    } finally {
      setPromoting(false)
    }
  }

  async function handleRemoveTool(tvId: string) {
    if (!vid) return
    try {
      await api.del(`/api/versions/${vid}/tool-assignments/${tvId}`)
      success('Tool removed')
      loadComposition()
    } catch {
      error('Could not remove tool')
    }
  }

  async function handleRemovePrompt(pvId: string, role: string) {
    if (!vid) return
    try {
      await api.del(`/api/versions/${vid}/prompt-assignments/${pvId}/${role}`)
      success('Assignment removed')
      loadComposition()
    } catch {
      error('Could not remove assignment')
    }
  }

  async function handleAssignPrompt(e: FormEvent) {
    e.preventDefault()
    if (!vid || assigning) return
    setAssigning(true)
    try {
      await api.post(`/api/versions/${vid}/prompt-assignments`, {
        prompt_version_id: promptVid,
        api_role_code: apiRole,
      })
      success('Prompt assigned')
      setPromptVid('')
      setShowPromptForm(false)
      loadComposition()
    } catch (err) {
      error(err instanceof ApiException ? err.body.detail : 'Assignment failed')
    } finally {
      setAssigning(false)
    }
  }

  if (!vid) return null
  if (version === null) return <div className="canvas-pad"><span className="input-hint">Loading…</span></div>

  const isChampion = version.lifecycle_stage === 'champion'

  const versionEntries: VersionEntry[] = allVersions.map((v) => ({
    id: v.executable_version_id,
    semver: v.semver,
    stage: v.lifecycle_stage,
  }))

  return (
    <div className="canvas-pad">
      <div className="page-head">
        <div>
          <div className="page-head__eyebrow">
            <Link to="/registry/tasks">Tasks</Link>
          </div>
          <div className="page-head__title">{task?.display_name ?? task?.name ?? 'Task'}</div>
          {task?.description && <div className="page-head__sub">{task.description}</div>}
          <div className="page-head__badges">
            {versionEntries.length > 0 && (
              <VersionSwitcher
                versions={versionEntries}
                currentId={vid}
                getTo={(v) => `/registry/tasks/${id}/versions/${v}`}
              />
            )}
            {task?.name && <span className="chip chip--code">{task.name}</span>}
            {task?.application_code && <span className="chip chip--app">{task.application_code}</span>}
            {version.governance_tier_code && <span className="chip chip--static">{version.governance_tier_code}</span>}
            {version.capability_type_code && <span className="chip chip--static">{version.capability_type_code}</span>}
          </div>
        </div>
        <div className="page-head__actions">
          {canPromote && !isChampion && (
            <button className="btn btn--secondary btn--sm" disabled={promoting} onClick={handlePromote}>
              Promote to champion
            </button>
          )}
        </div>
      </div>

      <section className="section">
        <div className="section__head"><span className="eyebrow">Metadata</span></div>
        <div className="kv">
          <span className="kv__k">Governance tier</span>
          <span className="kv__v">{version.governance_tier_code ?? '—'}</span>
          <span className="kv__k">Capability type</span>
          <span className="kv__v">{version.capability_type_code ?? '—'}</span>
          <span className="kv__k">Trust level</span>
          <span className="kv__v">{version.trust_level_code ?? '—'}</span>
          <span className="kv__k">Data classification</span>
          <span className="kv__v">{version.data_classification_code ?? '—'}</span>
        </div>
      </section>

      {/* Governing intake */}
      {intakeLink !== undefined && (
        <section className="section">
          <div className="section__head"><span className="eyebrow">Governing intake</span></div>
          {intakeLink === null ? (
            <div className="log-table">
              <EmptyState message="No intake linked to this asset." />
            </div>
          ) : (
            <div className="kv">
              <span className="kv__k">Intake</span>
              <span className="kv__v">
                <Link to={`/intakes/${intakeLink.intake_id}`}>{intakeLink.intake_title}</Link>
              </span>
              <span className="kv__k">Status</span>
              <span className="kv__v">
                <span className="chip chip--static">{intakeLink.intake_status_code}</span>
              </span>
            </div>
          )}
        </section>
      )}

      <section className="section">
        <div className="section__head"><span className="eyebrow">Inference config</span></div>
        {!inferenceConfig ? (
          <div className="log-table"><EmptyState message="No inference config assigned to this version." /></div>
        ) : (
          <>
            <div className="kv" style={{ marginBottom: 'var(--space-3)' }}>
              {inferenceConfig.max_tokens != null && (
                <><span className="kv__k">Max tokens</span><span className="kv__v">{inferenceConfig.max_tokens.toLocaleString()}</span></>
              )}
              {inferenceConfig.temperature != null && (
                <><span className="kv__k">Temperature</span><span className="kv__v">{inferenceConfig.temperature}</span></>
              )}
            </div>
            {inferenceConfig.model_references.length > 0 && (
              <div className="log-table">
                <div className="log-table__header model-ref-grid">
                  <span className="eyebrow">Priority</span>
                  <span className="eyebrow">Reference</span>
                  <span className="eyebrow">Resolved model</span>
                </div>
                {inferenceConfig.model_references.map((mr) => (
                  <div key={mr.model_reference_id} className="log-row model-ref-grid">
                    <span className="reg-count">{mr.priority}</span>
                    <span className="chip chip--static">{mr.reference_code}</span>
                    <span className="reg-entity-desc">{mr.resolved_model_code ?? '—'}</span>
                  </div>
                ))}
              </div>
            )}
          </>
        )}
      </section>

      <section className="section">
        <div className="section__head">
          <span className="eyebrow">Prompts</span>
          <span className="l-spacer" />
          {canAuthor && (
            <button className="btn btn--ghost btn--sm" onClick={() => setShowPromptForm((v) => !v)}>
              {showPromptForm ? 'Cancel' : '+ Assign prompt'}
            </button>
          )}
        </div>
        {showPromptForm && (
          <form className="l-cluster" onSubmit={handleAssignPrompt} style={{ marginBottom: 'var(--space-3)' }}>
            <input
              className="input"
              placeholder="Prompt version ID"
              value={promptVid}
              onChange={(e) => setPromptVid(e.target.value)}
              required
            />
            <select className="input" value={apiRole} onChange={(e) => setApiRole(e.target.value)}>
              <option value="system">system</option>
              <option value="user">user</option>
              <option value="assistant_prefill">assistant_prefill</option>
            </select>
            <button className="btn btn--secondary btn--sm" disabled={assigning || !promptVid}>Assign</button>
          </form>
        )}
        <div className="log-table">
          {prompts.length === 0 ? (
            <EmptyState message="No prompt assignments — assign a prompt to enable promotion." />
          ) : (
            <>
              <div className="log-table__header pa-grid">
                <span className="eyebrow">Ord</span>
                <span className="eyebrow">Role</span>
                <span className="eyebrow">Prompt</span>
                <span className="eyebrow">Version</span>
                <span className="eyebrow">Created</span>
                {canAuthor && <span />}
              </div>
              {prompts.map((pa) => {
                const compiled = promptDetails[pa.prompt_version_id]?.compiled
                return (
                  <div key={`${pa.prompt_version_id}:${pa.api_role_code}`}>
                    <div className="log-row pa-grid">
                      <span className="reg-count">{pa.ordinal}</span>
                      <span className="chip chip--static">{pa.api_role_code}</span>
                      <span>
                        <Link to={`/registry/prompts/${pa.prompt_id}/versions/${pa.prompt_version_id}`} className="reg-row-primary">
                          {pa.prompt_name}
                        </Link>
                      </span>
                      <span className="reg-entity-desc">{pa.prompt_semver}</span>
                      <span className="reg-entity-desc">{fmtTs(pa.created_at)}</span>
                      {canAuthor && (
                        <button className="btn btn--ghost btn--sm"
                                onClick={() => handleRemovePrompt(pa.prompt_version_id, pa.api_role_code)}>
                          Remove
                        </button>
                      )}
                    </div>
                    {compiled && (
                      <div className="log-row-expanded">
                        <pre className="code-block">{compiled}</pre>
                      </div>
                    )}
                  </div>
                )
              })}
            </>
          )}
        </div>
      </section>

      <section className="section">
        <div className="section__head"><span className="eyebrow">Authorized tools</span></div>
        <div className="log-table">
          {tools.length === 0 ? (
            <EmptyState message="No tool authorizations — this version makes no tool calls." />
          ) : (
            <>
              <div className="log-table__header ta-grid">
                <span className="eyebrow">Tool</span>
                <span className="eyebrow">Version</span>
                <span className="eyebrow">Created</span>
                {canAuthor && <span />}
              </div>
              {tools.map((ta) => {
                const td = toolDetails[ta.tool_version_id]
                return (
                  <div key={ta.tool_version_id}>
                    <div className="log-row ta-grid">
                      <Link to={`/registry/tools/${ta.tool_id}/versions/${ta.tool_version_id}`}
                            className="reg-row-primary">
                        {ta.tool_name}
                      </Link>
                      <span className="reg-entity-desc">{ta.tool_semver}</span>
                      <span className="reg-entity-desc">{fmtTs(ta.created_at)}</span>
                      {canAuthor && (
                        <button className="btn btn--ghost btn--sm"
                                onClick={() => handleRemoveTool(ta.tool_version_id)}>
                          Remove
                        </button>
                      )}
                    </div>
                    {td?.input_schema && (
                      <div className="log-row-expanded">
                        <div className="log-row-expanded__label">Input schema</div>
                        <pre className="code-block">{JSON.stringify(td.input_schema, null, 2)}</pre>
                      </div>
                    )}
                  </div>
                )
              })}
            </>
          )}
        </div>
      </section>

      <section className="section">
        <div className="section__head"><span className="eyebrow">Source bindings</span></div>
        <div className="log-table">
          {sources.length === 0 ? (
            <EmptyState message="No source bindings." />
          ) : (
            <>
              <div className="log-table__header binding-grid-src">
                <span className="eyebrow">Name</span>
                <span className="eyebrow">Kind</span>
                <span className="eyebrow">Delivery</span>
                <span className="eyebrow">Nullable</span>
              </div>
              {sources.map((sb) => (
                <div key={sb.source_binding_id} className="log-row binding-grid-src">
                  <span className="reg-row-primary">{sb.name}</span>
                  <span className="chip chip--static">{sb.source_kind_code.replace(/_/g, ' ')}</span>
                  <span className="reg-entity-desc">{sb.delivery_mode_code.replace(/_/g, ' ')}</span>
                  <span className="reg-entity-desc">{sb.nullable ? 'yes' : 'no'}</span>
                </div>
              ))}
            </>
          )}
        </div>
      </section>

      <section className="section">
        <div className="section__head"><span className="eyebrow">Target bindings</span></div>
        <div className="log-table">
          {targets.length === 0 ? (
            <EmptyState message="No target bindings." />
          ) : (
            <>
              <div className="log-table__header binding-grid-tgt">
                <span className="eyebrow">Name</span>
                <span className="eyebrow">Kind</span>
                <span className="eyebrow">Write mode</span>
              </div>
              {targets.map((tb) => (
                <div key={tb.target_binding_id} className="log-row binding-grid-tgt">
                  <span className="reg-row-primary">{tb.name}</span>
                  <span className="chip chip--static">{tb.target_kind_code.replace(/_/g, ' ')}</span>
                  <span className="reg-entity-desc">{tb.write_mode_code ?? '—'}</span>
                </div>
              ))}
            </>
          )}
        </div>
      </section>
    </div>
  )
}
