import type { HelpSnippet } from '../../types'

const fields: Record<string, HelpSnippet> = {
  compensating_controls: {
    label: 'Compensating controls',
    help: 'What mitigating controls are in place to compensate for not satisfying this obligation.',
    why: 'An exception without compensating controls is not approvable — the approver needs to evaluate the risk trade-off.',
  },
  rationale: {
    label: 'Rationale',
    help: 'Why this obligation cannot be satisfied in full.',
  },
  expires_at: {
    label: 'Expiry date',
    help: 'When this exception must be reviewed. Exceptions are time-limited.',
    why: 'Permanent exceptions are not allowed. Expiry forces a periodic review of the unmet obligation.',
  },
}
export default fields
