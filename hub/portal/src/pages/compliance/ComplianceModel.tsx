import { Fragment, useEffect, useState } from 'react'
import { Link } from 'react-router-dom'
import { api } from '@/api/client'
import type { ComplianceFramework, RequirementSummary } from '@/api/types'

// Read-only Compliance Model browser (FR-023) — the catalog. Frameworks + domain facets filter the
// canonical-requirement catalog (grouped by domain); each requirement links to its detail. The source
// of truth obligation resolution queries. Reuses canonical classes — no new CSS.

const DOMAIN_LABEL: Record<string, string> = {
  model_risk: 'Model risk', fairness: 'Fairness', privacy: 'Privacy', data_governance: 'Data governance',
  human_oversight: 'Human oversight', transparency: 'Transparency', robustness: 'Robustness',
  security: 'Security', accountability: 'Accountability',
}
export const domainLabel = (c: string) => DOMAIN_LABEL[c] ?? c

export function ComplianceModel() {
  const [frameworks, setFrameworks] = useState<ComplianceFramework[]>([])
  const [reqs, setReqs] = useState<RequirementSummary[]>([])
  const [fw, setFw] = useState('')
  const [dm, setDm] = useState('')

  useEffect(() => {
    api.get<ComplianceFramework[]>('/api/compliance/frameworks').then(setFrameworks).catch(() => setFrameworks([]))
    api.get<RequirementSummary[]>('/api/compliance/requirements').then(setReqs).catch(() => setReqs([]))
  }, [])

  const shown = reqs.filter((r) => (!fw || r.frameworks.includes(fw)) && (!dm || r.governance_domain_code === dm))
  const domains = [...new Set(reqs.map((r) => r.governance_domain_code))].sort()
  const byDomain = domains.map((d) => ({ d, items: shown.filter((r) => r.governance_domain_code === d) })).filter((g) => g.items.length)

  return (
    <div className="canvas-pad">
      <div className="page-head">
        <div>
          <div className="page-head__title">Compliance model</div>
          <div className="page-head__sub">The governed metamodel — frameworks, canonical requirements, cumulative tier ladders, controls and evidence. Obligation resolution queries this; editing is a governed follow-on.</div>
        </div>
      </div>

      <div className="card">
        <div className="rail-panel__title">Frameworks</div>
        <div className="l-cluster" role="group" aria-label="Filter by framework">
          <button className={`chip${fw === '' ? ' is-selected' : ''}`} onClick={() => setFw('')}>All</button>
          {frameworks.filter((f) => f.requirement_count > 0).map((f) => (
            <button key={f.framework_code} className={`chip${fw === f.framework_code ? ' is-selected' : ''}`} onClick={() => setFw(fw === f.framework_code ? '' : f.framework_code)}>
              {f.name} · {f.requirement_count}
            </button>
          ))}
        </div>
      </div>

      <div className="card">
        <div className="rail-panel__title">Domains</div>
        <div className="l-cluster" role="group" aria-label="Filter by domain">
          <button className={`chip${dm === '' ? ' is-selected' : ''}`} onClick={() => setDm('')}>All</button>
          {domains.map((d) => (
            <button key={d} className={`chip${dm === d ? ' is-selected' : ''}`} onClick={() => setDm(dm === d ? '' : d)}>{domainLabel(d)}</button>
          ))}
        </div>
      </div>

      {byDomain.map((g) => (
        <div className="card" key={g.d}>
          <div className="rail-panel__title">{domainLabel(g.d)} · {g.items.length}</div>
          <div className="kv">
            {g.items.map((r) => (
              <Fragment key={r.requirement_code}>
                <span className="kv__k"><Link to={`/compliance/requirements/${r.requirement_code}`}>{r.requirement_code}</Link></span>
                <span className="kv__v">
                  <strong>{r.title}</strong>
                  <div className="l-cluster">
                    {r.frameworks.map((f) => <span key={f} className="chip chip--static">{f}</span>)}
                    <span className="u-text-tertiary">tiers 1–{r.max_tier ?? '?'} · {r.control_count} controls</span>
                  </div>
                </span>
              </Fragment>
            ))}
          </div>
        </div>
      ))}
      {shown.length === 0 && <div className="card"><p className="input-hint">No requirements match the filters.</p></div>}
    </div>
  )
}
