export interface HelpPageEntry {
  path: string
  title: string
  subtitle?: string
  group: 'Reference' | 'Forms' | 'Workflows' | 'How-To' | 'Roles'
  stub?: true
}

export const HELP_PAGES: HelpPageEntry[] = [
  // Reference
  { path: 'overview.product',  title: 'About Verity',   subtitle: 'What the platform governs and why it exists', group: 'Reference' },
  { path: 'overview.glossary', title: 'Glossary',        subtitle: 'Key terms: intake, obligation, tier, registry asset…', group: 'Reference' },
  // Forms
  { path: 'forms.assessment',           title: 'Assessment Form',     subtitle: 'Decision type, data, oversight, risks, fairness', group: 'Forms' },
  { path: 'forms.intake-create',        title: 'Create Intake',       subtitle: 'Register a new AI use case for review', group: 'Forms' },
  { path: 'forms.application-onboard',  title: 'Onboard Application', subtitle: 'Register an AI system or product', group: 'Forms' },
  { path: 'forms.evidence-record',      title: 'Record Evidence',     subtitle: 'Capture evidence for a compliance obligation', group: 'Forms' },
  { path: 'forms.exception-raise',      title: 'Raise Exception',     subtitle: 'Request a waiver for an unmet control', group: 'Forms' },
  { path: 'forms.change-proposal',      title: 'Change Proposal',     subtitle: 'Propose a risk or business change to an intake', group: 'Forms' },
  { path: 'forms.registry-asset',       title: 'Registry Asset',      subtitle: 'Create or version an AI asset in the registry', group: 'Forms' },
  // Workflows
  { path: 'workflows.intake-approval',        title: 'Intake Approval',        subtitle: 'Create → assess → submit → quorum → approved', group: 'Workflows' },
  { path: 'workflows.obligation-resolution',  title: 'Obligation Resolution',  subtitle: 'Review controls → evidence → exceptions → resolved', group: 'Workflows' },
  { path: 'workflows.registry-promotion',     title: 'Registry Promotion',     subtitle: 'Register → link intake → advance lifecycle', group: 'Workflows' },
  // How-To
  { path: 'how-to.submit-intake',          title: 'Submit an Intake',           subtitle: 'Step-by-step: create, assess, submit, get approved', group: 'How-To' },
  { path: 'how-to.resolve-obligations',    title: 'Resolve Obligations',        subtitle: 'Record evidence and raise exceptions', group: 'How-To' },
  { path: 'how-to.advance-registry-asset', title: 'Advance a Registry Asset',  subtitle: 'From draft to champion via the lifecycle', group: 'How-To' },
  { path: 'how-to.raise-change-proposal',  title: 'Raise a Change Proposal',   subtitle: 'Risk reclassification and business changes', group: 'How-To' },
  // Registry 005
  { path: 'how-to.registry-entity-types',   title: 'Registry Entity Types',   subtitle: 'Agents, tasks, prompts, tools, and models — what they are', group: 'Reference' },
  { path: 'how-to.registry-compose',        title: 'Composing an Agent',       subtitle: 'Assign prompts, tools, and MCP servers to a version', group: 'Forms' },
  { path: 'how-to.registry-full-lifecycle', title: 'Full Registry Lifecycle',  subtitle: 'Draft → candidate → challenger → champion', group: 'Workflows' },
  { path: 'how-to.registry-navigate',       title: 'Navigating the Registry',  subtitle: 'Find agents, tasks, prompts, tools, and models', group: 'How-To' },
  // Roles
  { path: 'roles.overview',    title: 'Roles Overview',     subtitle: 'All roles and separation of duty', group: 'Roles' },
  { path: 'roles.underwriter', title: 'Underwriter',        subtitle: 'Assess use cases; submit and sign off on approvals', group: 'Roles' },
  { path: 'roles.compliance',  title: 'Compliance Officer', subtitle: 'Approve exceptions; sign off on compliance-sensitive intakes', group: 'Roles' },
  { path: 'roles.risk',        title: 'Risk Manager',       subtitle: 'Oversee risk tier decisions; approve high-risk exceptions', group: 'Roles' },
]
