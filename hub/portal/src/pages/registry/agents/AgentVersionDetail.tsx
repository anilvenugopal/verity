import { type FormEvent, useCallback, useEffect, useState } from 'react'
import { Link, useParams } from 'react-router-dom'
import { api, ApiException } from '@/api/client'
import { useSession } from '@/auth/useSession'
import { useToast } from '@/shell/useToast'
import type {
  DelegationSummary,
  ExecutableVersion,
  InferenceConfigDetail,
  IntakeLink,
  McpAssignment,
  PromptAssignment,
  SourceBinding,
  TargetBinding,
  ToolAssignment,
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

export function AgentVersionDetail() {
  const { id, vid } = useParams<{ id: string; vid: string }>()
  const { canDo } = useSession()
  const { success, error } = useToast()
  const canAuthor = canDo('author_registry')
  const canPromote = canDo('promote_registry')

  const [version, setVersion] = useState<ExecutableVersion | null>(null)
  const [agent, setAgent] = useState<{ name: string; display_name?: string | null; description?: string | null; application_code?: string | null; application_name?: string | null } | null>(null)
  const [intakeLink, setIntakeLink] = useState<IntakeLink | null | undefined>(undefined)
  const [allVersions, setAllVersions] = useState<ExecutableVersion[]>([])
  const [prompts, setPrompts] = useState<PromptAssignment[]>([])
  const [tools, setTools] = useState<ToolAssignment[]>([])
  const [mcps, setMcps] = useState<McpAssignment[]>([])
  const [sources, setSources] = useState<SourceBinding[]>([])
  const [targets, setTargets] = useState<TargetBinding[]>([])
  const [delegations, setDelegations] = useState<DelegationSummary[]>([])
  const [inferenceConfig, setInferenceConfig] = useState<InferenceConfigDetail | null>(null)
  const [promoting, setPromoting] = useState(false)

  // Assign-prompt form state
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
    api.get<McpAssignment[]>(`/api/versions/${vid}/mcp-assignments`).then(setMcps).catch(() => setMcps([]))
    api.get<SourceBinding[]>(`/api/versions/${vid}/source-bindings`).then(setSources).catch(() => setSources([]))
    api.get<TargetBinding[]>(`/api/versions/${vid}/target-bindings`).then(setTargets).catch(() => setTargets([]))
    api.get<DelegationSummary[]>(`/api/versions/${vid}/delegations`).then(setDelegations).catch(() => setDelegations([]))
  }, [vid])

  useEffect(() => {
    if (!id) return
    api.get<typeof agent>(`/api/executables/${id}`).then(setAgent).catch(() => {})
    api.get<ExecutableVersion[]>(`/api/executables/${id}/versions`).then(setAllVersions).catch(() => {})
    api.get<IntakeLink>(`/api/executables/${id}/intake-link`).then(setIntakeLink).catch(() => setIntakeLink(null))
  }, [id])

  useEffect(() => {
    loadVersion()
    loadComposition()
  }, [loadVersion, loadComposition])

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
      {/* Page head */}
      <div className="page-head">
        <div>
          <div className="page-head__eyebrow">
            <Link to="/registry/agents">Agents</Link>
          </div>
          <div className="page-head__title">{agent?.display_name ?? agent?.name ?? 'Agent'}</div>
          {agent?.description && <div className="page-head__sub">{agent.description}</div>}
          <div className="page-head__badges">
            {versionEntries.length > 0 && (
              <VersionSwitcher
                versions={versionEntries}
                currentId={vid}
                getTo={(v) => `/registry/agents/${id}/versions/${v}`}
              />
            )}
            {agent?.name && <span className="chip chip--code">{agent.name}</span>}
            {agent?.application_code && <span className="chip chip--app">{agent.application_code}</span>}
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

      {/* Metadata */}
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
          <span className="kv__k">Inference config</span>
          <span className="kv__v">{version.inference_config_id ? <code style={{ fontSize: 'var(--fs-mono)' }}>{version.inference_config_id}</code> : '—'}</span>
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
                <span className={`chip chip--static`}>{intakeLink.intake_status_code}</span>
              </span>
            </div>
          )}
        </section>
      )}

      {/* Inference config */}
      <section className="section">
        <div className="section__head"><span className="eyebrow">Inference config</span></div>
        {!inferenceConfig ? (
          <div className="log-table">
            <EmptyState message="No inference config assigned to this version." />
          </div>
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

      {/* Prompt assignments */}
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
                {canAuthor && <span />}
              </div>
              {prompts.map((pa) => (
                <div key={`${pa.prompt_version_id}:${pa.api_role_code}`}
                     className="log-row pa-grid">
                  <span className="reg-count">{pa.ordinal}</span>
                  <span className="chip chip--static">{pa.api_role_code}</span>
                  <span>
                    <Link to={`/registry/prompts/${pa.prompt_version_id.split(':')[0]}`} className="reg-row-primary">
                      {pa.prompt_name}
                    </Link>
                  </span>
                  <span className="reg-entity-desc">{pa.prompt_semver}</span>
                  {canAuthor && (
                    <button className="btn btn--ghost btn--sm"
                            onClick={() => handleRemovePrompt(pa.prompt_version_id, pa.api_role_code)}>
                      Remove
                    </button>
                  )}
                </div>
              ))}
            </>
          )}
        </div>
      </section>

      {/* Authorized tools */}
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
                {canAuthor && <span />}
              </div>
              {tools.map((ta) => (
                <div key={ta.tool_version_id}
                     className="log-row ta-grid">
                  <Link to={`/registry/tools/${ta.tool_version_id.split(':')[0]}`}
                        className="reg-row-primary">
                    {ta.tool_name}
                  </Link>
                  <span className="reg-entity-desc">{ta.tool_semver}</span>
                  {canAuthor && (
                    <button className="btn btn--ghost btn--sm"
                            onClick={() => handleRemoveTool(ta.tool_version_id)}>
                      Remove
                    </button>
                  )}
                </div>
              ))}
            </>
          )}
        </div>
      </section>

      {/* Sub-agent delegations */}
      <section className="section">
        <div className="section__head"><span className="eyebrow">Sub-agent delegations</span></div>
        <div className="log-table">
          {delegations.length === 0 ? (
            <EmptyState message="No delegations — this agent runs without sub-agent calls." />
          ) : (
            <>
              <div className="log-table__header delegation-grid">
                <span className="eyebrow">Child agent</span>
                <span className="eyebrow">Tracking</span>
                <span className="eyebrow">Rationale</span>
              </div>
              {delegations.map((d) => (
                <div key={d.delegation_id} className="log-row delegation-grid">
                  <div className="reg-entity-cell">
                    {d.child_name ? (
                      d.child_kind === 'agent'
                        ? <Link to={`/registry/agents/${d.child_executable_id}`} className="reg-row-primary">{d.child_name}</Link>
                        : <span className="reg-row-primary">{d.child_name}</span>
                    ) : (
                      <code style={{ fontSize: 'var(--fs-mono)' }}>{d.child_version_id ?? '—'}</code>
                    )}
                  </div>
                  <span className={d.child_executable_id ? 'chip chip--track' : 'chip chip--pinned'}>
                    {d.child_executable_id ? 'champion' : 'pinned'}
                  </span>
                  <span className="reg-entity-desc" style={{ overflow: 'hidden', display: '-webkit-box', WebkitLineClamp: 2, WebkitBoxOrient: 'vertical' }}>
                    {d.rationale ?? '—'}
                  </span>
                </div>
              ))}
            </>
          )}
        </div>
      </section>

      {/* Source bindings */}
      <section className="section">
        <div className="section__head"><span className="eyebrow">Source bindings</span></div>
        <div className="log-table">
          {sources.length === 0 ? (
            <EmptyState message="No source bindings — version reads no declared input sources." />
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

      {/* Target bindings */}
      <section className="section">
        <div className="section__head"><span className="eyebrow">Target bindings</span></div>
        <div className="log-table">
          {targets.length === 0 ? (
            <EmptyState message="No target bindings — version writes to no declared outputs." />
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

      {/* MCP servers (show only when present) */}
      {mcps.length > 0 && (
        <section className="section">
          <div className="section__head"><span className="eyebrow">MCP servers</span></div>
          <div className="log-table">
            <div className="log-table__header mcp-srv-grid">
              <span className="eyebrow">Server</span>
              <span className="eyebrow">Version</span>
            </div>
            {mcps.map((ma) => (
              <div key={ma.mcp_server_version_id} className="log-row mcp-srv-grid">
                <span className="reg-row-primary">{ma.name}</span>
                <span className="reg-entity-desc">{ma.semver}</span>
              </div>
            ))}
          </div>
        </section>
      )}
    </div>
  )
}
