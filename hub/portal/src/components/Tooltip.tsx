import { useCallback, useRef, useState } from 'react'
import { createPortal } from 'react-dom'

// Portal tooltip. The bubble renders at <body> via createPortal, so it escapes overflow:hidden/auto
// ancestors that clip the pure-CSS [data-tooltip] (sidebars, tables). Position is computed from the
// trigger's rect on hover/focus. Usage: spread `anchor` onto the trigger element, render `tip` inside
// it (the portal places it at body regardless). CSS: .tooltip (components.css).
export function useTooltip<T extends HTMLElement = HTMLElement>(label?: string | null) {
  const ref = useRef<T>(null)
  const [pos, setPos] = useState<{ top: number; left: number } | null>(null)

  const show = useCallback(() => {
    const r = ref.current?.getBoundingClientRect()
    if (r) setPos({ top: r.top - 6, left: r.left + r.width / 2 })
  }, [])
  const hide = useCallback(() => setPos(null), [])

  const anchor = label ? { ref, onMouseEnter: show, onMouseLeave: hide, onFocus: show, onBlur: hide } : {}
  const tip =
    label && pos
      ? createPortal(
          <span
            className="tooltip"
            role="tooltip"
            style={{ top: pos.top, left: pos.left, transform: 'translate(-50%, -100%)' }}
          >
            {label}
          </span>,
          document.body,
        )
      : null

  return { anchor, tip }
}
