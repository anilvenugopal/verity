import { useEffect, useState } from 'react'
import { Navigate, useNavigate, useParams } from 'react-router-dom'
import { api } from '@/api/client'
import type { ApprovalRequest } from '@/api/types'

// /approvals/:id is now a thin redirect into the application workspace, where the governance rail
// lives. Application-kind approvals resolve to /applications/{target}. (Intake-kind lands with M4.)
export function ApprovalRedirect() {
  const { id } = useParams<{ id: string }>()
  const navigate = useNavigate()
  const [appId, setAppId] = useState<string | null>(null)
  const [failed, setFailed] = useState(false)

  useEffect(() => {
    if (!id) return
    api.get<ApprovalRequest>(`/api/approvals/${id}`)
      .then((a) => (a.target_application_id ? setAppId(a.target_application_id) : setFailed(true)))
      .catch(() => setFailed(true))
  }, [id])

  if (appId) return <Navigate to={`/applications/${appId}`} replace />
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
