import { useHelp } from '@/help/useHelp'
import { helpDrawer } from './HelpDrawer'

// Renders a ? button that opens a native Popover API panel containing the help snippet.
// React 18 doesn't type popovertarget / popover as props, so we set them via ref callbacks
// on the DOM elements — the browser only needs the attributes present in the DOM.
export function HelpPopover({ helpId }: { helpId: string }) {
  const snippet = useHelp(helpId)
  if (!snippet) return null

  // Derive the page path: strip .fields.<key> to get the form/workflow root
  // e.g. 'forms.assessment.fields.decision_type' → 'forms.assessment'
  const pagePath = helpId.replace(/\.fields\.[^.]+$/, '').replace(/\.steps\.[^.]+$/, '')
  const hasPage = pagePath !== helpId

  const popId = `hp-${helpId.replace(/[^a-z0-9]/gi, '-')}`

  return (
    <>
      <button
        type="button"
        ref={(el) => el?.setAttribute('popovertarget', popId)}
        className="help-popover__trigger"
        aria-label={`Help: ${snippet.label}`}
      >?</button>
      <div
        id={popId}
        ref={(el) => el?.setAttribute('popover', 'auto')}
        className="help-popover__panel"
      >
        <strong className="help-popover__label">{snippet.label}</strong>
        <p className="help-popover__body">{snippet.help}</p>
        {hasPage && (
          <button
            type="button"
            className="help-popover__more"
            onClick={() => {
              helpDrawer.open(pagePath)
              document.getElementById(popId)?.hidePopover()
            }}
          >Learn more →</button>
        )}
      </div>
    </>
  )
}
