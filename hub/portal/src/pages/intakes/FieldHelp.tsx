import { useState } from 'react'
import { createPortal } from 'react-dom'
import { useTooltip } from '@/components/Tooltip'
import type { FieldDef } from './assessmentCatalog'

// A form label paired with the three-layer help pattern (FR-026): the label, a (?) trigger whose
// hover shows the inline definition (tooltip), and — for consequential fields — a click-through
// "Learn more" modal explaining why it matters and what each option implies. Reuses the canonical
// .modal/.overlay; the .fhelp* classes are page-local (Assessment.css).
export function FieldHelp({ field, required, htmlFor }: { field: FieldDef; required?: boolean; htmlFor?: string }) {
  const [open, setOpen] = useState(false)
  const { anchor, tip } = useTooltip<HTMLButtonElement>(field.help)
  const hasModal = !!(field.why || field.options?.some((o) => o.note))
  return (
    <span className="fhelp">
      <label className={`form-label${required ? ' is-required' : ''}`} htmlFor={htmlFor}>{field.label}</label>
      <button
        type="button"
        className="fhelp__q"
        aria-label={`About ${field.label}`}
        {...anchor}
        onClick={hasModal ? () => setOpen(true) : undefined}
      >?</button>
      {tip}
      {open && hasModal && createPortal(
        <div className="overlay" onClick={() => setOpen(false)}>
          <div className="modal modal--help" role="dialog" aria-modal="true" aria-label={field.label} onClick={(e) => e.stopPropagation()}>
            <div className="prefs__header">
              <div className="prefs__title">{field.label}</div>
              <button className="sidebar__toggle" onClick={() => setOpen(false)} aria-label="Close">
                <svg className="icon" aria-hidden="true"><use href="#i-clear" /></svg>
              </button>
            </div>
            <div className="modal__body">
              <p className="fhelp__why">{field.help}{field.why ? ` ${field.why}` : ''}</p>
              {field.options?.filter((o) => o.note).map((o) => (
                <div className="fhelp__opt" key={o.value}>
                  <div className="fhelp__opt__label">{o.label}</div>
                  <div className="fhelp__opt__note">{o.note}</div>
                </div>
              ))}
            </div>
          </div>
        </div>,
        document.body,
      )}
    </span>
  )
}
