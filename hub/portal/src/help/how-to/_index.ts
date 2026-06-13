import type { HelpPageLoader } from '../types'

export interface HowToEntry {
  title: string
  page: HelpPageLoader
}

const howToIndex: Record<string, HowToEntry> = {
  'submit-intake':          { title: 'Submit an intake',                page: () => import('./submit-intake.html?raw') },
  'resolve-obligations':    { title: 'Resolve obligations',             page: () => import('./resolve-obligations.html?raw') },
  'advance-registry-asset': { title: 'Advance a registry asset',        page: () => import('./advance-registry-asset.html?raw') },
  'raise-change-proposal':  { title: 'Raise a change proposal',         page: () => import('./raise-change-proposal.html?raw') },
  'registry-entity-types':  { title: 'Registry entity types',           page: () => import('./registry-entity-types.html?raw') },
  'registry-compose':       { title: 'Composing an agent version',      page: () => import('./registry-compose.html?raw') },
  'registry-full-lifecycle':{ title: 'Full registry lifecycle',          page: () => import('./registry-full-lifecycle.html?raw') },
  'registry-navigate':      { title: 'Navigating the registry',         page: () => import('./registry-navigate.html?raw') },
}
export default howToIndex
