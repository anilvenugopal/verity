import type { WorkflowStep } from '../../types'

const steps: WorkflowStep[] = [
  { id: 'create', title: 'Create intake', body: 'Propose the use case under an active application. Provide a title and description.' },
  { id: 'assess', title: 'Complete assessment', body: 'Fill all five assessment sections. The system computes the risk tier on save.', note: 'All sections must be valid before the tier can be computed.' },
  { id: 'submit', title: 'Submit for approval', body: 'Submit once a tier is computed. The tier determines the approver quorum.' },
  { id: 'quorum', title: 'Quorum sign-off', body: 'Required approvers review the assessment and sign off. All required roles must approve.', note: 'Separation of duty: the submitter cannot approve their own request.' },
  { id: 'approved', title: 'Approved', body: 'The intake is approved. Obligations are resolved from the compliance metamodel. Registry assets can now advance to production.' },
]
export default steps
