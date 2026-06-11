// Re-exports the assessment catalog as the canonical corpus entry for this form.
// FieldDef in assessmentCatalog.ts is structurally identical to HelpSnippet — no changes needed.
import { FIELDS } from '@/pages/intakes/assessmentCatalog'
import type { HelpSnippet } from '../../types'

const fields: Record<string, HelpSnippet> = FIELDS
export default fields
