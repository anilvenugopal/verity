// Reference-table-driven badge. Give it a reference list (`table`) + a `code`; it pulls the row's
// label (text), description (tooltip, always), tone (colour) and icon (sprite, else a dot) from the
// cached reference data. Display flags (quiet/iconOnly/noIcon/size) are placement-local — the page
// decides how a badge sits in its context. CSS: styles/badges.css (tone palette + display mods).
import { useReferenceCodes } from '@/api/reference'
import { useTooltip } from './Tooltip'

export interface BadgeProps {
  table: string // reference list, e.g. 'application_status'
  code: string // the value
  category?: string // semantic hook → .badge-{category}; defaults to table name with _ → -
  quiet?: boolean
  iconOnly?: boolean
  noIcon?: boolean
  size?: 'sm' | 'lg'
}

export function Badge({ table, code, category, quiet, iconOnly, noIcon, size }: BadgeProps) {
  const row = useReferenceCodes(table)[code]
  const label = row?.label ?? code
  const { anchor, tip } = useTooltip<HTMLSpanElement>(row?.description) // description → tooltip, always
  const cat = category ?? table.replace(/_/g, '-')
  const cls = [
    'badge',
    `badge-${cat}`,
    quiet && 'badge--quiet',
    iconOnly && 'badge--icon-only',
    noIcon && 'badge--no-icon',
    size === 'sm' && 'badge--sm',
    size === 'lg' && 'badge--lg',
  ]
    .filter(Boolean)
    .join(' ')

  return (
    <span className={cls} data-code={code} data-tone={row?.tone ?? undefined} {...anchor}>
      {row?.icon ? (
        <svg className="badge__icon" aria-hidden="true"><use href={`#${row.icon}`} /></svg>
      ) : (
        <span className="badge__dot" />
      )}
      <span className="badge__label">{label}</span>
      {tip}
    </span>
  )
}
