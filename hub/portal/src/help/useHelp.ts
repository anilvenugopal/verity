import { helpManifest } from './_manifest'
import type { HelpSnippet, HelpPageLoader } from './types'

// Walk the manifest by dot-separated path. Returns null for unknown paths rather than throwing.
// Examples:
//   useHelp('forms.assessment.fields.decision_type')
//   useHelp('forms.intake-create.fields.title')
export function useHelp(path: string): HelpSnippet | null {
  const parts = path.split('.')
  // eslint-disable-next-line @typescript-eslint/no-explicit-any
  let node: any = helpManifest
  for (const part of parts) {
    if (node == null || typeof node !== 'object') return null
    node = node[part]
  }
  if (node == null || typeof node !== 'object' || typeof node.label !== 'string') return null
  return node as HelpSnippet
}

// Resolve a page loader by dot-separated path. Returns null for unknown paths.
// Examples:
//   useHelpPage('forms.assessment')          → loader for assessment _page.html
//   useHelpPage('workflows.intake-approval') → loader for intake-approval _page.html
//   useHelpPage('overview.glossary')         → loader for glossary.html
export function useHelpPage(path: string): HelpPageLoader | null {
  const parts = path.split('.')
  // eslint-disable-next-line @typescript-eslint/no-explicit-any
  let node: any = helpManifest
  for (const part of parts) {
    if (node == null || typeof node !== 'object') return null
    node = node[part]
  }
  if (node == null) return null
  // FormHelp / WorkflowHelp / RoleHelp each have a .page loader
  if (typeof node.page === 'function') return node.page as HelpPageLoader
  // overview entries are loaders directly
  if (typeof node === 'function') return node as HelpPageLoader
  return null
}
