import type { HelpSnippet } from '../../types'

const fields: Record<string, HelpSnippet> = {
  name: {
    label: 'Asset name',
    help: 'The name of the AI model, agent, or task being registered.',
  },
  kind_code: {
    label: 'Kind',
    help: 'The type of executable asset.',
    options: [
      { value: 'task', label: 'Task', note: 'A discrete, invocable AI operation.' },
      { value: 'agent', label: 'Agent', note: 'An autonomous multi-step AI process.' },
    ],
  },
  version: {
    label: 'Version',
    help: 'A semver identifier for this asset version.',
    why: 'Each version tracks its own lifecycle stage independently. A new version starts at draft and must advance through the governance lifecycle.',
  },
  lifecycle_stage: {
    label: 'Lifecycle stage',
    help: 'The governance stage of this asset version.',
    why: 'Promotion to challenger or champion is blocked unless the asset is linked to an approved intake with resolved obligations — this is the promotion gate.',
    options: [
      { value: 'draft', label: 'Draft', note: 'In development. No governance constraints.' },
      { value: 'candidate', label: 'Candidate', note: 'Ready for governance review.' },
      { value: 'staging', label: 'Staging', note: 'Under review.' },
      { value: 'challenger', label: 'Challenger', note: 'Requires approved intake + resolved obligations.' },
      { value: 'champion', label: 'Champion', note: 'Production. Requires approved intake + resolved obligations.' },
      { value: 'deprecated', label: 'Deprecated', note: 'Retired.' },
    ],
  },
}
export default fields
