// Atomic help unit — matches the existing FieldDef shape from assessmentCatalog.ts exactly.
// assessmentCatalog.ts re-exports FieldDef as an alias of HelpSnippet for backward compatibility.
export interface HelpSnippet {
  label: string
  help: string
  why?: string
  options?: { value: string; label: string; note?: string }[]
}

// FieldDef alias — assessmentCatalog.ts consumers need no change
export type FieldDef = HelpSnippet

export interface WorkflowStep {
  id: string
  title: string
  body: string
  note?: string
}

// Vite ?raw dynamic import — resolves to { default: string }
export type HelpPageLoader = () => Promise<{ default: string }>

export interface FormHelp {
  fields: Record<string, HelpSnippet>
  page: HelpPageLoader
}

export interface WorkflowHelp {
  steps: WorkflowStep[]
  page: HelpPageLoader
}

export interface RoleHelp {
  page: HelpPageLoader
}
