import { useEffect, useState } from 'react'
import { Navigate, useNavigate, useParams } from 'react-router-dom'
import { api } from '@/api/client'
import type { ApprovalRequest } from '@/api/types'

// /approvals/:id is a thin redirect to wherever the governance rail lives: an application-kind
// approval resolves to /applications/{target}, an intake-kind approval to /intakes/{target}.
export function ApprovalRedirect() {
  const { id } = useParams<{ id: string }>()
  const navigate = useNavigate()
  const [to, setTo] = useState<string | null>(null)
  const [failed, setFailed] = useState(false)

  useEffect(() => {
    if (!id) return
    api.get<ApprovalRequest>(`/api/approvals/${id}`)
      .then((a) => {
        if (a.target_application_id) setTo(`/applications/${a.target_application_id}`)
        else if (a.target_intake_id) setTo(`/intakes/${a.target_intake_id}`)
        else setFailed(true)
      })
      .catch(() => setFailed(true))
  }, [id])

  if (to) return <Navigate to={to} replace />
  if (failed) {
    return (
      <div className="canvas-pad"><div className="card"><div className="empty-state">
        <div className="empty-state__title">Approval not available</div>
        <div className="empty-state__actions">
          <button className="btn btn--secondary btn--md" onClick={() => navigate('/applications')}>Back to applications</button>
        </div>
      </div></div></div>
    )
  }
  return <div className="canvas-pad"><div className="card"><div className="empty-state"><div className="empty-state__body">Loading…</div></div></div></div>
}
