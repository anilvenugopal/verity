import { useEffect, useState } from 'react'
import { useNavigate, useParams } from 'react-router-dom'
import { api, ApiException } from '@/api/client'
import { useSession } from '@/auth/useSession'
import type { Application } from '@/api/types'
import { Badge } from '@/components/Badge'

interface Code { code: string; label: string }
interface Ref {
  data_classifications: Code[]
  lines_of_business: Code[]
  frameworks: Code[]
  governance_domains: Code[]
  jurisdictions: Code[]
}

const labelOf = (codes: Code[] | undefined, code: string | null) =>
  (code && codes?.find((c) => c.code === code)?.label) || code || '—'

// Application detail (read-only Overview): identity + compliance perimeter from GET /applications/{id},
// codes resolved to labels via /reference/onboarding. Use cases / Team / Activity arrive with M4's
// backend — not faked here. Row→detail target for the registry.
export function ApplicationDetail() {
  const { id } = useParams<{ id: string }>()
  const navigate = useNavigate()
  const { principal } = useSession()
  const [app, setApp] = useState<Application | null>(null)
  const [ref, setRef] = useState<Ref | null>(null)
  const [notFound, setNotFound] = useState(false)

  useEffect(() => {
    if (!id) return
    api.get<Application>(`/api/applications/${id}`).then(setApp).catch((e) => {
      if (e instanceof ApiException && e.status === 404) setNotFound(true)
    })
    api.get<Ref>('/api/reference/onboarding').then(setRef).catch(() => undefined)
  }, [id])

  if (notFound) {
    return (
      <div className="canvas-pad">
        <div className="card"><div className="empty-state">
          <div className="empty-state__title">Application not found</div>
          <div className="empty-state__actions">
            <button className="btn btn--secondary btn--md" onClick={() => navigate('/applications')}>Back to applications</button>
          </div>
        </div></div>
      </div>
    )
  }
  if (!app) {
    return <div className="canvas-pad"><div className="card"><div className="empty-state"><div className="empty-state__body">Loading…</div></div></div></div>
  }

  const yn = (v: boolean) => <span className={`yn yn--${v ? 'y' : 'n'}`}>{v ? 'Yes' : 'No'}</span>
  const owned = principal && app.business_owner_actor_id === principal.actor_id
  const onboarded = new Date(app.created_at).toLocaleDateString(undefined, { day: 'numeric', month: 'short', year: 'numeric' })

  return (
    <div className="canvas-pad">
      <div className="page-head">
        <div>
          <div className="page-head__title l-cluster">
            {app.name} <span className="tla">{app.code}</span>
            <Badge table="application_status" code={app.application_status_code} quiet />
          </div>
          <div className="page-head__sub">
            Owner: {owned ? `${principal?.display_name} · you` : '—'}
            {' · '}{labelOf(ref?.lines_of_business, app.line_of_business_code)}
            {' · '}onboarded {onboarded}
          </div>
        </div>
      </div>

      <div className="l-grid l-grid--2col">
        <div className="card">
          <div className="section__head"><span className="eyebrow">Identity</span></div>
          <div className="kv">
            <span className="kv__k">Purpose</span><span className="kv__v">{app.description}</span>
            <span className="kv__k">Line of business</span><span className="kv__v">{labelOf(ref?.lines_of_business, app.line_of_business_code)}</span>
            <span className="kv__k">Data ceiling</span><span className="kv__v">{labelOf(ref?.data_classifications, app.data_classification_code)}</span>
          </div>
        </div>

        <div className="card">
          <div className="section__head"><span className="eyebrow">Compliance perimeter</span></div>
          <div className="kv">
            <span className="kv__k">Frameworks</span>
            <span className="kv__v">{app.regulatory_framework_codes.map((c) => <span key={c} className="chip chip--static">{labelOf(ref?.frameworks, c)}</span>)}</span>
            <span className="kv__k">Domains</span>
            <span className="kv__v">{app.governance_domain_codes.map((c) => <span key={c} className="chip chip--static">{labelOf(ref?.governance_domains, c)}</span>)}</span>
            <span className="kv__k">Consumer impact</span>
            <span className="kv__v">Decisions affecting consumers {yn(app.affects_consumers)} · PII/PHI {yn(app.processes_pii)} · Consumer-facing {yn(app.consumer_facing)}</span>
            <span className="kv__k">Jurisdictions</span>
            <span className="kv__v">{app.jurisdiction_codes.map((c) => <span key={c} className="chip chip--static">{labelOf(ref?.jurisdictions, c)}</span>)}</span>
          </div>
        </div>
      </div>
    </div>
  )
}
