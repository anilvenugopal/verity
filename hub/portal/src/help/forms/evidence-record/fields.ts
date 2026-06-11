import type { HelpSnippet } from '../../types'

const fields: Record<string, HelpSnippet> = {
  control_code: {
    label: 'Control',
    help: 'The oversight control this evidence satisfies.',
    why: 'Each obligation has one or more controls. Recording evidence against a control moves the obligation toward satisfied status.',
  },
}
export default fields
