// Navigation metamodel (zero-trust): a nav item exists ONLY if it's declared here. Each node is a
// (target, mode) pair. Targets are app | page | action (objects are an in-page concern, not nav).
//
// The `requires` gate is COSMETIC affordance only — it decides what's *shown*. The real authority is
// the API (action matrix + RLS); routes/endpoints enforce independently. Resolution: filter by the
// affordance gate, then a constrained postProcess hook for the ~20% that needs custom treatment.

export type NavKind = 'app' | 'page' | 'action'

export interface NavNode {
  key: string
  kind: NavKind
  label: string
  desc?: string // presentation only (launcher tiles)
  icon: string // sprite id
  to?: string // app/page route (omitted = not yet built; shown but inert)
  action?: string // kind:'action' — the action code (also its mode intent)
  mode?: string // optional landing mode; capabilities are resolved on the destination
  scope?: 'global' | 'application'
  requires?: string // affordance gate: an action code or role; omitted = visible to all
  section?: string // sidebar group label (eyebrow); ungrouped if omitted
  badge?: string | number // sidebar static badge (presentation)
  count?: { provider: string; cap?: number } // OPTIONAL live count badge: provider resolves to a
  // number in the shell; if it exceeds `cap` we render `${cap}+` instead of the exact value.
  children?: NavNode[] // sidebar nodes under an app
}

// The manifest. Only Home routes in US2; the other apps are the shell's map, wired as their
// features land (Intake → US3, Studio/Registry/… later). No `requires` yet — apps are visible to
// any authenticated user; per-app gating is added when those areas exist.
export const NAV: NavNode[] = [
  { key: 'home', kind: 'app', label: 'Home', desc: 'Landing & getting started', icon: 'i-app-home', to: '/' },
  {
    key: 'intake', kind: 'app', label: 'Intake', desc: 'Onboard applications', icon: 'i-app-intake', to: '/applications',
    children: [
      { key: 'applications', kind: 'page', label: 'Applications', icon: 'i-entity-application', to: '/applications', section: 'Intake', count: { provider: 'applications', cap: 99 } },
      { key: 'usecases', kind: 'page', label: 'Use cases', icon: 'i-entity-task', section: 'Intake' },
      { key: 'obligations', kind: 'page', label: 'Obligations', icon: 'i-app-compliance', section: 'Intake' },
      // actions — bottom-stacked under an ACTIONS header (the recorded design)
      { key: 'onboard-app', kind: 'action', label: 'Onboard app.', icon: 'i-add', to: '/applications/new', requires: 'onboard_application' },
      { key: 'intake-uc', kind: 'action', label: 'Intake use case', icon: 'i-add' },
    ],
  },
  { key: 'studio', kind: 'app', label: 'Studio', desc: 'Author agents & tasks', icon: 'i-app-studio' },
  { key: 'registry', kind: 'app', label: 'Registry', desc: 'Entities & versions', icon: 'i-app-registry' },
  { key: 'observability', kind: 'app', label: 'Observability', desc: 'Runs & traces', icon: 'i-app-observability' },
  { key: 'governance', kind: 'app', label: 'Governance', desc: 'Lifecycle & approvals', icon: 'i-app-governance' },
  { key: 'compliance', kind: 'app', label: 'Compliance', desc: 'Audit & evidence', icon: 'i-app-compliance' },
  { key: 'harness', kind: 'app', label: 'Harness', desc: 'Runtime cluster', icon: 'i-app-harness' },
]

// A custom hook may group / reorder / relabel / inject STATIC nodes — but injected nodes are
// re-gated, so it can never surface what the gate hid.
export type NavPostProcess = (nodes: NavNode[]) => NavNode[]

/** Resolve the manifest for a principal: affordance-filter, recurse into children, then postProcess
 *  (re-gated). `can(req)` is the cosmetic gate — true if the principal could perform/hold `req`. */
export function resolveNav(
  nodes: NavNode[],
  can: (req: string) => boolean,
  postProcess?: NavPostProcess,
): NavNode[] {
  const gate = (n: NavNode) => !n.requires || can(n.requires)
  const filtered = nodes
    .filter(gate)
    .map((n) => (n.children ? { ...n, children: resolveNav(n.children, can) } : n))
  if (!postProcess) return filtered
  // re-gate anything the hook injected, so add-ons can't bypass the gate
  return postProcess(filtered).filter(gate)
}
