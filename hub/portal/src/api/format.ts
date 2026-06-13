const _fmt = new Intl.DateTimeFormat(undefined, {
  year: 'numeric', month: 'short', day: 'numeric',
  hour: '2-digit', minute: '2-digit',
})

export function fmtTs(ts: string | null | undefined): string {
  if (!ts) return '—'
  return _fmt.format(new Date(ts))
}
