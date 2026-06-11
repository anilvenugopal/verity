import { Fragment, useEffect, useState } from 'react'
import { Link, useParams } from 'react-router-dom'
import { api, ApiException } from '@/api/client'
import type { RequirementDetail } from '@/api/types'
import { domainLabel } from './ComplianceModel'

// Read-only Compliance Model browser (FR-023) — requirement detail. Shows the source provisions
// (citations + min tier), the cumulative tier ladder, and per tier the SMART controls
// (phase · type · enforcement) + the evidence that proves them. Reuses canonical classes — no new CSS.

export function ComplianceRequirement() {
  const { code } = useParams<{ code: string }>()
  const [d, setD] = useState<RequirementDetail | null>(null)
  const [err, setErr] = useState('')

  useEffect(() => {
    if (!code) return
    api.get<RequirementDetail>(`/api/compliance/requirements/${code}`)
      .then(setD)
      .catch((e) => setErr(e instanceof ApiException ? e.body.detail : 'Requirement not found'))
  }, [code])

  if (err) return (
    <div className="canvas-pad"><div className="card"><div className="empty-state">
      <div className="empty-state__title">{err}</div>
      <div className="empty-state__actions"><Link className="btn btn--secondary btn--md" to="/compliance/model">Back to model</Link></div>
    </div></div></div>
  )
  if (!d) return <div className="canvas-pad"><div className="card"><div className="empty-state"><div className="empty-state__body">Loading…</div></div></div></div>

  return (
    <div className="canvas-pad">
      <div className="breadcrumb">
        <Link to="/compliance/model" className="breadcrumb__item">Compliance model</Link>
        <span className="breadcrumb__sep">/</span>
        <span className="breadcrumb__item">{d.requirement_code}</span>
      </div>
      <div className="page-head"><div>
        <div className="page-head__title">{d.title}</div>
        <div className="page-head__sub">{d.text}</div>
      </div></div>

      <div className="card">
        <div className="rail-panel__title">Identity</div>
        <div className="kv">
          <span className="kv__k">Code</span><span className="kv__v">{d.requirement_code}</span>
          <span className="kv__k">Domain</span><span className="kv__v"><span className="chip chip--static">{domainLabel(d.governance_domain_code)}</span></span>
        </div>
      </div>

      <div className="card">
        <div className="rail-panel__title">Source provisions</div>
        <div className="kv">
          {d.provisions.map((p, i) => (
            <Fragment key={i}>
              <span className="kv__k"><span className="chip chip--static">{p.framework_code}</span></span>
              <span className="kv__v">{p.citation} <span className="u-text-tertiary">· applies from tier {p.min_tier_level}</span></span>
            </Fragment>
          ))}
        </div>
      </div>

      <div className="card">
        <div className="rail-panel__title">Tier ladder · cumulative (tier N implies 1…N)</div>
        <div className="kv">
          {d.tiers.map((t) => (
            <Fragment key={t.tier_level}>
              <span className="kv__k">Tier {t.tier_level}</span>
              <span className="kv__v">
                <strong>{t.title}</strong>
                <div className="u-text-tertiary">{t.criteria}</div>
                {t.controls.map((c) => (
                  <div className="l-cluster" key={c.control_code}>
                    <span>{c.title}</span>
                    <span className="chip chip--static">{c.control_phase_code}</span>
                    <span className="chip chip--static">{c.control_type_code}</span>
                    <span className="chip chip--static">enforce: {c.enforcement_action_code}</span>
                    {c.evidence.map((e) => <span key={e.evidence_artifact_type_code} className="chip chip--static">evidence: {e.evidence_artifact_type_code}</span>)}
                  </div>
                ))}
              </span>
            </Fragment>
          ))}
        </div>
      </div>
    </div>
  )
}
