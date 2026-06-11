import { useNavigate } from 'react-router-dom'

interface ErrorScreenProps {
  title: string
  detail?: string
  id?: string
  action?: { label: string; to: string }
}

export function ErrorScreen({ title, detail, id, action }: ErrorScreenProps) {
  const navigate = useNavigate()
  return (
    <div className="page-takeover">
      <div className="page-takeover__body">
        <h1 className="page-takeover__title">{title}</h1>
        {detail && <p className="page-takeover__detail">{detail}</p>}
        {id && <p className="page-takeover__id">Error ID: <code>{id}</code></p>}
        {action && (
          <button className="btn btn--primary" onClick={() => navigate(action.to)}>
            {action.label}
          </button>
        )}
      </div>
    </div>
  )
}
