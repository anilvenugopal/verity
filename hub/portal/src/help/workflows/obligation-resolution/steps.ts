import type { WorkflowStep } from '../../types'

const steps: WorkflowStep[] = [
  { id: 'review', title: 'Review obligations', body: 'After intake approval, obligations are resolved from the compliance metamodel based on the risk tier and governance domains.' },
  { id: 'evidence', title: 'Record evidence', body: 'For each obligation control, record evidence of implementation. All controls evidenced = obligation satisfied.' },
  { id: 'exception', title: 'Raise exception', body: 'For obligations that cannot be satisfied, raise a time-limited exception with compensating controls and rationale.', note: 'Exceptions require approval by a compliance or security approver (separation of duty).' },
  { id: 'resolve', title: 'Resolved', body: 'All obligations satisfied or excepted. The intake is fully resolved and registry assets can be promoted to production.' },
]
export default steps
