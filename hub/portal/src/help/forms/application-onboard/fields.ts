import type { HelpSnippet } from '../../types'

const fields: Record<string, HelpSnippet> = {
  name: {
    label: 'Application name',
    help: 'The name of the AI application or system.',
  },
  code: {
    label: 'Code',
    help: 'Short identifier used in reporting and audit trails.',
  },
  description: {
    label: 'Description',
    help: 'What this application does and its purpose within the organisation.',
  },
  data_classification_code: {
    label: 'Data classification ceiling',
    help: 'The highest sensitivity tier of data this application handles.',
    why: 'Sets the classification ceiling for all use cases (intakes) under this application.',
  },
  affects_consumers: {
    label: 'Affects consumers',
    help: 'Does this application make or support decisions that affect policyholders or applicants?',
  },
  processes_pii: {
    label: 'Processes PII / PHI',
    help: 'Does this application process personal or health information?',
  },
  consumer_facing: {
    label: 'Consumer-facing',
    help: 'Does the application interact directly with consumers (e.g. a chatbot, portal, or recommendation engine)?',
  },
  line_of_business_code: {
    label: 'Line of business',
    help: 'The primary line of business this application serves.',
  },
  business_owner_actor_id: {
    label: 'Business owner',
    help: 'The accountable owner. Receives approval requests and is responsible for governance compliance.',
  },
}
export default fields
