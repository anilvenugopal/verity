import { useEffect } from 'react'
import { useToasts, removeToast, type ToastItem, type ToastTone } from './ToastContext'
import { helpDrawer } from './HelpDrawer'

const ICONS: Record<ToastTone, string> = {
  success: '✓',
  error: '✕',
  warning: '⚠',
  info: 'ℹ',
}

const AUTO_DISMISS_MS = 4000

function ToastEntry({ item }: { item: ToastItem }) {
  useEffect(() => {
    if (!item.autoDismiss) return
    const t = setTimeout(() => removeToast(item.id), AUTO_DISMISS_MS)
    return () => clearTimeout(t)
  }, [item.id, item.autoDismiss])

  return (
    <div className={`toast toast--${item.tone}`} role="alert" aria-live="polite">
      <span className="toast__icon" aria-hidden="true">{ICONS[item.tone]}</span>
      <span className="toast__message">{item.message}</span>
      {item.helpId && (
        <button className="toast__help" onClick={() => helpDrawer.open(item.helpId!)}>Learn more →</button>
      )}
      <button
        className="toast__dismiss"
        aria-label="Dismiss"
        onClick={() => removeToast(item.id)}
      >✕</button>
    </div>
  )
}

export function Toast() {
  const toasts = useToasts()
  if (toasts.length === 0) return null
  return (
    <div className="toast-stack" aria-label="Notifications">
      {toasts.map((t) => <ToastEntry key={t.id} item={t} />)}
    </div>
  )
}
