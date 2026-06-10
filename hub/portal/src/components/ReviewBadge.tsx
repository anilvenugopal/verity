import type { Application } from '@/api/types'
import { Badge } from './Badge'

// The display status for an application. An active/suspended/retired app shows its application_status
// (the governed lifecycle state). A *pending* app shows a DERIVED review status from its latest
// approval — so "rejected" and "in review" don't both read as plain "Pending". Derived = display only,
// not a persisted status code.
export interface ReviewState { label: string; tone: string }

export function reviewState(app: Application): ReviewState | null {
  if (app.application_status_code !== 'pending') return null // use the governed status badge
  const latest = app.latest_approval_status
  if (!latest || latest === 'cancelled') return { label: 'Draft', tone: 'neutral' }
  if (latest === 'pending') return { label: 'In review', tone: 'info' }
  if (latest === 'rejected') {
    return app.latest_decision === 'requested_changes'
      ? { label: 'Changes requested', tone: 'warning' }
      : { label: 'Rejected', tone: 'negative' }
  }
  return { label: 'In review', tone: 'info' }
}

// Renders the review status for a pending app (derived, tone-coloured), else the canonical
// application_status <Badge>. Display flags mirror <Badge>.
export function ReviewBadge({ app, quiet, size }: { app: Application; quiet?: boolean; size?: 'sm' | 'lg' }) {
  const rs = reviewState(app)
  if (!rs) return <Badge table="application_status" code={app.application_status_code} quiet={quiet} size={size} />
  const cls = ['badge', quiet && 'badge--quiet', size === 'sm' && 'badge--sm', size === 'lg' && 'badge--lg'].filter(Boolean).join(' ')
  return (
    <span className={cls} data-tone={rs.tone}>
      <span className="badge__dot" />
      <span className="badge__label">{rs.label}</span>
    </span>
  )
}
