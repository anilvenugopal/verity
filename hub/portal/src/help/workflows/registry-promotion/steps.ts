import type { WorkflowStep } from '../../types'

const steps: WorkflowStep[] = [
  { id: 'register', title: 'Register asset', body: 'Create the asset and its first version in the registry. Starts at draft.' },
  { id: 'link', title: 'Link to intake', body: 'Link the asset to an approved intake via the Risk & Obligations tab.', note: 'The intake must be approved and obligations resolved before advancing to production stages.' },
  { id: 'advance', title: 'Advance lifecycle', body: 'Advance through candidate → staging → challenger → champion. The promotion gate blocks challenger/champion until the linked intake is approved with resolved obligations.' },
]
export default steps
