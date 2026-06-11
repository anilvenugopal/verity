import type { HelpSnippet } from '../../types'

const fields: Record<string, HelpSnippet> = {
  title: {
    label: 'Use case title',
    help: 'A short, descriptive name for this AI use case.',
    why: 'The title is the primary identifier in approval workflows and reporting.',
  },
  description: {
    label: 'Description',
    help: 'What this AI system does and how it is used.',
  },
  application_id: {
    label: 'Application',
    help: 'The governed application this intake belongs to.',
    why: 'An intake must belong to an active, approved application. The application sets the regulatory frameworks and jurisdiction context that constrain this use case.',
  },
}
export default fields
