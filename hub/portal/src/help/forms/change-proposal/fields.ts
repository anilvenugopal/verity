import type { HelpSnippet } from '../../types'

const fields: Record<string, HelpSnippet> = {
  kind_code: {
    label: 'Proposal kind',
    help: 'The type of change being proposed.',
    why: 'Risk reclassification triggers re-assessment and re-resolution of obligations. Business change documents a material operational change and forks any impacted assets to a new draft.',
    options: [
      { value: 'risk_reclassification', label: 'Risk reclassification', note: 'Re-runs the tier computation. Impacted assets are forked on approval.' },
      { value: 'business_change', label: 'Business change', note: 'Documents a material change to how the use case is operated.' },
    ],
  },
  asset_ids: {
    label: 'Impacted assets',
    help: 'Registry assets whose lifecycle is affected by this change.',
    why: 'Approved proposals fork linked assets to a new draft, requiring re-promotion through the governance lifecycle.',
  },
}
export default fields
