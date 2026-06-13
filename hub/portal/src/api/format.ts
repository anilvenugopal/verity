const _fmt = new Intl.DateTimeFormat(undefined, {
  year: 'numeric', month: 'short', day: 'numeric',
  hour: '2-digit', minute: '2-digit', timeZoneName: 'short',
})

const _fmtDate = new Intl.DateTimeFormat(undefined, {
  year: 'numeric', month: 'short', day: 'numeric',
})

export function fmtTs(ts: string | null | undefined): string {
  if (!ts) return '—'
  return _fmt.format(new Date(ts))
}

export function fmtDate(ts: string | null | undefined): string {
  if (!ts) return '—'
  return _fmtDate.format(new Date(ts))
}
