# Feature Specification: Shell Polish + Dev Environment Hardening

**Feature Branch**: `004-shell-polish`

**Created**: 2026-06-11

**Status**: Draft

**Input**: Roadmap feature 004 (shell.toast / shell.help / shell.error) plus dev-environment hardening requested in session: clean Python venv discipline, proactive browser-error catching via TypeScript strictness, VSCode Testing tab wiring, Node version pinning, `./dev` test integration, and test coverage strategy.

## Overview

Feature 004 is two complementary slabs of work that must land together because they share the same goal: **confidence**. The first is user-facing — the portal currently gives no feedback on write operations and has no error states. Every form submit either silently succeeds or silently fails. The second is developer-facing — the dev environment has no enforced Python interpreter discipline, no proactive TypeScript safety net beyond `strict`, no test runner wired into VSCode or `./dev`, and zero portal test coverage.

Both slabs are small individually. Together they make every subsequent feature faster and safer.

---

## Slab A — Shell Polish (user-facing)

### A1 · Toast notification system (`shell.toast`)

Transient feedback for every write operation in the portal. Operations that take >300ms show a spinner; those that take >2s and complete show a toast. Manual dismiss + auto-expire. Four tones: `success`, `warning`, `error`, `info`.

**Corpus amendment**: The `toast()` function accepts an optional fourth parameter `helpId?: string`. When provided, the toast renders a "Learn more →" link that opens the relevant help page in `HelpDrawer`. This makes error toasts actionable — e.g., a 422 on the risk-tier field links to `forms.assessment.fields.risk_tier`. No change to existing call sites; the parameter is purely additive.

**Wiring targets** (every existing write path that currently has no feedback):
- Application onboard form submit / approval signoff
- Intake create / submit-for-approval / signoff
- Assessment save
- Evidence record / exception raise / exception signoff
- Registry asset create / lifecycle advance / intake link
- Change proposal raise / signoff

**User scenarios**:
1. Submit a form → spinner appears after 300ms if not yet complete → on success a green toast appears and auto-expires after 4s.
2. An API error (4xx/5xx) → red error toast appears with the server's `detail` message; does not auto-expire (requires dismiss).
3. A network failure (fetch throws) → red "Network error — check your connection" toast.
4. Long operation (e.g. assessment save with obligation resolution) → spinner persists until the response arrives.

### A2 · Contextual help (`shell.help`)

A `?` icon affordance per section/field. Clicking it opens a compact popover with inline explainer copy. For consequential fields, clicking through opens a full help modal/drawer.

`FieldHelp.tsx` + `assessmentCatalog.ts` already implement this pattern for the assessment form (tooltip on hover, modal on click with `why` + option notes). US3 wires the popover into section headers using content resolved from the help corpus (see Slab C below). Full cross-portal rollout is part of Slab C.

**Amendment to original scope**: `HelpPopover` accepts `helpId: string` (resolved from the corpus manifest), not an inline `content: string` prop. Co-located content is replaced by corpus-backed content. US3 depends on the Slab C foundation tasks being complete first.

### A3 · Error states (`shell.error`)

Three states the portal currently does not handle:
- **404 / not found** — clean "This page doesn't exist" UI with a back-to-home link; catches bad UUIDs in `/intakes/:id`, `/applications/:id`, etc.
- **Forbidden (403)** — "You don't have permission to view this" with a link to the landing page.
- **Generic failure** — catch-all route (`*`) and a React error boundary that catches unexpected JS errors; shows a "Something went wrong" screen with an error ID (generated client-side) and a reload button; logs the error to the console.

---

## Slab B — Dev Environment Hardening (developer-facing)

### B1 · Python venv discipline

**Problem**: `uv` manages `hub/.venv` but there is nothing stopping a developer (or VSCode) from picking up a system Python and running tests or the server against wrong/missing dependencies.

**What is needed**:
- `.vscode/settings.json` pinning `python.defaultInterpreterPath` to `hub/.venv/bin/python` ✓ *(partially done — created in session, not yet committed)*
- A `hub/.python-version` file so `uv` and tools that respect that file (pyenv, direnv) always activate the same Python version.
- A root-level `Makefile` or extension to `tools/dev.py` so `make test` / `dev test` always runs `uv run pytest` from `hub/` — never `python -m pytest` from root with an unknown interpreter.
- Document the rule in `hub/CONTRIBUTING.md` (or a new `docs/dev-setup.md`): *"Never `pip install`. Never `python -m pytest`. Always `uv run` from `hub/` or use the VSCode Testing tab."*

### B2 · TypeScript strictness — `noUncheckedIndexedAccess` ✓

Already enabled in `tsconfig.app.json` in the previous session. All `Record<K,V>[key]` and `Array[i]` lookups now return `V | undefined` — a missing catalog entry is a **compile error**, not a silent crash. This is committed as part of 003.

What remains: document the rule in a brief `hub/portal/CONTRIBUTING.md` or inline comment in `tsconfig.app.json` so future contributors understand why it's there and don't revert it.

### B3 · Node version pinning

No `.nvmrc` or `engines` field exists. Node 24 is whatever is on the host. This is a latent inconsistency risk across machines.

**What is needed**:
- `.nvmrc` at `hub/portal/` (or repo root) pinned to the current version (`24`).
- `engines: { "node": ">=24" }` in `hub/portal/package.json`.
- Document in dev-setup: "Use `nvm use` from `hub/portal/` or install Node 24 directly."

### B4 · VSCode Testing tab wiring

`.vscode/settings.json` created in session wires pytest to the hub venv and the correct `cwd`. That covers Python.

For portal (TypeScript/Vitest): the Vitest VSCode extension (`vitest.explorer`) is available but there are currently zero test files. The configuration in `settings.json` is already in place (`vitest.workspaceConfig`). The gap is test files.

**What is needed**:
- At least one Vitest test file to validate the wiring: `hub/portal/src/shell/__tests__/nav.test.ts` — test `resolveNav` (pure function, no DOM, no mocks needed). This also establishes the test file convention and confirms Vitest runs in the Testing tab.

### B5 · `./dev` test integration

`tools/dev.py` currently only manages `up`, `down`, `status`. It does not have a `test` command. Running tests requires knowing to `cd hub && uv run pytest`.

**What is needed**:
- `dev test` command that runs `uv run pytest` from `hub/` with the correct env (same env dict as `_hub_env()`), streaming output.
- `dev test:portal` command that runs `npm run test` from `hub/portal/`.
- Both commands print the interpreter/runtime being used so it is transparent.

### B6 · Test coverage baseline and strategy

Current state:
- Python: 67 tests, all integration (testcontainers PG18). No unit tests. No coverage measurement.
- Portal (TypeScript): 0 tests.

**What is needed for 004**:
- Add `pytest-cov` to hub dev deps; add `--cov=verity.hub --cov-report=term-missing` to the `dev test` command output.
- Establish coverage targets in `pyproject.toml` (`[tool.coverage.report] fail_under = 70` as a starting floor — not aspirational, just a ratchet).
- Write 3–5 portal unit tests covering the pure-function layer: `resolveNav`, `assessmentCatalog` field presence (the test that would have caught the `classification` crash), and the `api/client.ts` error-handling path.
- These are not exhaustive — they establish the pattern and prove the tooling works end-to-end.

---

## Slab C — Help Documentation Corpus (US6)

### C1 · Architecture overview

A file-based help corpus that formalizes and extends the existing `assessmentCatalog.ts` / `FieldHelp.tsx` pattern to every form, workflow, and role in the portal. No database. The manifest is the metamodel.

**Guiding principle**: `assessmentCatalog.ts`'s `FieldDef` (`label`, `help`, `why`, `options[].note`) is already the canonical snippet primitive. The corpus adopts this shape as `HelpSnippet` and applies it everywhere. `FieldDef` is re-exported as an alias of `HelpSnippet` for backward compatibility.

### C2 · Types

```ts
// hub/portal/src/help/types.ts

// Atomic help unit — matches the existing FieldDef shape exactly
export interface HelpSnippet {
  label: string
  help: string            // inline tooltip body (always shown)
  why?: string            // why-it-matters (click-through modal/drawer body)
  options?: { value: string; label: string; note?: string }[]
}

// Step in a workflow how-to
export interface WorkflowStep {
  id: string
  title: string
  body: string            // prose description (1–3 sentences)
  note?: string           // optional guidance / caveat
}

// Lazy HTML page loader (avoids bundling all help content upfront)
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
```

### C3 · Folder structure

```
hub/portal/src/help/
  types.ts                      ← HelpSnippet, WorkflowStep, HelpPageLoader, FormHelp, WorkflowHelp, RoleHelp
  _manifest.ts                  ← typed index — the metamodel
  forms/
    assessment/
      fields.ts                 ← re-exports from assessmentCatalog.ts (FieldDef ≡ HelpSnippet)
      _page.html                ← full assessment form help page
    intake-create/
      fields.ts                 ← applicant_name, application_id, description, …
      _page.html
    application-onboard/
      fields.ts                 ← name, org_type, contact_email, …
      _page.html
    evidence-record/
      fields.ts                 ← obligation_id, evidence_text, source_url, …
      _page.html
    exception-raise/
      fields.ts                 ← reason, risk_acknowledged, …
      _page.html
    change-proposal/
      fields.ts                 ← kind, rationale, affected_assets, …
      _page.html
    registry-asset/
      fields.ts                 ← name, kind, version, …
      _page.html
  workflows/
    intake-approval/
      steps.ts                  ← create → assess → submit → quorum-signoff → approved
      _page.html
    registry-promotion/
      steps.ts                  ← register → link-intake → advance-lifecycle
      _page.html
    obligation-resolution/
      steps.ts                  ← review obligations → record evidence → raise exception → resolve
      _page.html
  roles/
    _overview.html              ← all roles, what each can do
    underwriter.html
    compliance-officer.html
    risk-manager.html
  how-to/
    _index.ts                   ← maps how-to ids to { title, page: HelpPageLoader }
    submit-intake.html
    resolve-obligations.html
    advance-registry-asset.html
    raise-change-proposal.html
  overview/
    product.html                ← product overview; what Verity governs and why
    glossary.html               ← intake, obligation, tier, registry asset, …
```

### C4 · Manifest

```ts
// hub/portal/src/help/_manifest.ts
import type { FormHelp, WorkflowHelp, RoleHelp, HelpPageLoader } from './types'
import assessmentFields from './forms/assessment/fields'
import intakeCreateFields from './forms/intake-create/fields'
// … other form field imports (static — HelpSnippet objects are small)

export const helpManifest = {
  forms: {
    assessment:           { fields: assessmentFields,    page: () => import('./forms/assessment/_page.html?raw') } as FormHelp,
    'intake-create':      { fields: intakeCreateFields,  page: () => import('./forms/intake-create/_page.html?raw') } as FormHelp,
    'application-onboard':{ fields: applicationOnboardFields, page: () => import('./forms/application-onboard/_page.html?raw') } as FormHelp,
    'evidence-record':    { fields: evidenceRecordFields, page: () => import('./forms/evidence-record/_page.html?raw') } as FormHelp,
    'exception-raise':    { fields: exceptionRaiseFields, page: () => import('./forms/exception-raise/_page.html?raw') } as FormHelp,
    'change-proposal':    { fields: changeProposalFields, page: () => import('./forms/change-proposal/_page.html?raw') } as FormHelp,
    'registry-asset':     { fields: registryAssetFields, page: () => import('./forms/registry-asset/_page.html?raw') } as FormHelp,
  },
  workflows: {
    'intake-approval':       { steps: intakeApprovalSteps,    page: () => import('./workflows/intake-approval/_page.html?raw') } as WorkflowHelp,
    'registry-promotion':    { steps: registryPromotionSteps, page: () => import('./workflows/registry-promotion/_page.html?raw') } as WorkflowHelp,
    'obligation-resolution': { steps: obligationResolutionSteps, page: () => import('./workflows/obligation-resolution/_page.html?raw') } as WorkflowHelp,
  },
  roles: {
    overview:    { page: () => import('./roles/_overview.html?raw') } as RoleHelp,
    underwriter: { page: () => import('./roles/underwriter.html?raw') } as RoleHelp,
    compliance:  { page: () => import('./roles/compliance-officer.html?raw') } as RoleHelp,
    risk:        { page: () => import('./roles/risk-manager.html?raw') } as RoleHelp,
  },
  'how-to': howToIndex,
  overview: {
    product:  () => import('./overview/product.html?raw'),
    glossary: () => import('./overview/glossary.html?raw'),
  },
} as const
```

**Dot-path addressing**: `helpManifest.forms['intake-create'].fields.applicant_name` or resolved via the `useHelp` hook as `'forms.intake-create.fields.applicant_name'`.

**Build-time safety**: `?raw` Vite imports are type-checked at build time — a missing file is a compile error. No runtime manifest/file divergence.

### C5 · Runtime hooks and components

```ts
// hub/portal/src/help/useHelp.ts

// Resolve a HelpSnippet by dot-path. Returns null if path not found.
// Examples:
//   useHelp('forms.assessment.fields.decision_type')
//   useHelp('forms.intake-create.fields.applicant_name')
export function useHelp(path: string): HelpSnippet | null

// Resolve a page loader by dot-path. Returns null if path not found.
// Examples:
//   useHelpPage('forms.assessment')
//   useHelpPage('workflows.intake-approval')
//   useHelpPage('overview.glossary')
export function useHelpPage(path: string): HelpPageLoader | null
```

```tsx
// hub/portal/src/shell/HelpDrawer.tsx
// Renders a help page (HTML) in the existing modal/overlay shell.
// Opened via helpDrawer.open(path) — a module-level singleton similar to toastEmitter.
// Closed by Escape, backdrop click, or explicit close().
interface HelpDrawerProps {}  // no props — driven by the singleton

export function HelpDrawer(): JSX.Element  // mounted once in App.tsx
export const helpDrawer = { open(path: string): void, close(): void }
```

### C6 · Integration points

**HelpPopover (US3 amendment)**: `HelpPopover` accepts `helpId: string`. Internally calls `useHelp(helpId)` for the snippet and `useHelpPage(helpId.replace('.fields.*', ''))` for the "Learn more" page link. No inline content props.

```tsx
// Before (original T024):
<HelpPopover content={section.why} id={sectionId} />

// After (amended T024):
<HelpPopover helpId="forms.assessment.fields.decision_type" />
```

**FieldHelp (existing — no change required)**: Continues to receive `FieldDef` from `assessmentCatalog.ts`. The catalog is re-exported through `help/forms/assessment/fields.ts` so `FieldHelp` is implicitly corpus-backed without any code change.

**Toast (amendment to A1)**: `toast(message, tone, autoDismiss?, helpId?)`. The `Toast.tsx` component renders a `<button>` or `<a>` — "Learn more →" — when `helpId` is present, calling `helpDrawer.open(helpId)`.

**Help route**: `/help/:path*` renders `HelpDrawer` fullscreen — allows deep-linking to help pages from onboarding emails or the command palette.

### C7 · HTML page format

Help pages are HTML fragments (not full documents). They are injected into `HelpDrawer` via `innerHTML`. Structure convention:

```html
<!-- forms/intake-create/_page.html -->
<article class="help-page">
  <header class="help-page__header">
    <h1>Create Intake</h1>
    <p class="help-page__subtitle">Register a new AI use case for governance review.</p>
  </header>

  <section class="help-page__section">
    <h2>Purpose</h2>
    <p>An intake captures the details of an AI system...</p>
  </section>

  <section class="help-page__section">
    <h2>Fields</h2>
    <dl class="help-page__fields">
      <dt>Applicant name</dt>
      <dd>The person or team accountable for this use case...</dd>
    </dl>
  </section>

  <section class="help-page__section">
    <h2>What happens next</h2>
    <p>After submission, the intake enters the assessment queue...</p>
  </section>
</article>
```

CSS for `.help-page*` lives in `hub/portal/src/styles/help.css` — a new file, not extending `components.css`. It is the only place allowed to style help page content.

### C8 · Validation and build integrity

A Vitest test (`hub/portal/src/help/__tests__/manifest.test.ts`) verifies at build time:
- Every key in `helpManifest.forms[*].fields` has a non-empty `label` and `help` string.
- Every `HelpPageLoader` in the manifest is a function (import exists — Vite's `?raw` import will have already failed the build if the file is missing, but this catches manifest typos).
- Every `helpId` string referenced in `HelpPopover` and `toast()` call sites resolves in the manifest (done via a regex scan + manifest key enumeration in the test).

---

## Acceptance Criteria

### Shell (A1–A3)
1. Every write operation in the portal shows a spinner if >300ms and a toast on completion or error.
2. API error responses surface their `detail` message in a dismissible error toast.
3. A bad UUID in a detail route renders a 404 screen, not a blank page or JS crash.
4. A 403 response renders a forbidden screen.
5. An unexpected JS error is caught by the error boundary and renders a recovery screen instead of a blank page.
6. The `?` affordance on assessment form fields opens a popover resolved from the help corpus; "Learn more" opens `HelpDrawer` with the full page.
7. An error toast with a `helpId` renders a "Learn more →" link that opens `HelpDrawer` at the correct page.

### Help corpus (C1–C8)
1. `hub/portal/src/help/_manifest.ts` compiles without errors; every `?raw` import resolves to an existing file.
2. `useHelp('forms.assessment.fields.decision_type')` returns the `FieldDef` entry from `assessmentCatalog.ts`.
3. `useHelpPage('forms.intake-create')` returns a loader; calling it returns an HTML string.
4. `HelpDrawer` renders any corpus page at `/help/:path*` and via `helpDrawer.open(path)`.
5. The manifest validation Vitest test passes — every snippet has `label` + `help`; every loader is a function.
6. `tsc --noEmit` fails if a `helpId` string references a manifest key that doesn't exist (enforced via branded type or test scan — pick one).
7. `FieldHelp.tsx` is unchanged — `assessmentCatalog.ts` continues to work as before; the corpus re-export is transparent.

### Dev (B1–B6)
1. `cd hub && uv run pytest` and VSCode Testing tab both discover and run all 67 tests with the same interpreter.
2. `dev test` runs `uv run pytest` and prints coverage; `dev test:portal` runs Vitest.
3. `tsc --noEmit` fails if a new `sel()` call references a key not in `assessmentCatalog.ts`.
4. `hub/portal/` has at least 3 passing Vitest tests visible in the VSCode Testing tab.
5. `hub/.python-version` and `hub/portal/.nvmrc` exist and pin the correct versions.
6. A `dev test` run shows ≥70% coverage for `verity.hub`.

---

## Key FRs and References

- Wireframe catalog §0: `shell.toast`, `shell.help`, `shell.error`
- Feature roadmap 004 (`specs/features/feature-roadmap.md`)
- `.vscode/settings.json` (created in session, to be committed as part of 004)
- `noUncheckedIndexedAccess` (enabled in `tsconfig.app.json`, committed in 003)
- `hub/portal/src/pages/intakes/assessmentCatalog.ts` — existing `FieldDef` is the canonical `HelpSnippet` shape
- `hub/portal/src/pages/intakes/FieldHelp.tsx` — existing tooltip+modal component; re-used unchanged

## Dependencies

- **Depends on**: 002 (portal scaffold + CSS kit), 003 (all existing write paths to wire toast into)
- **Blocks**: all subsequent UI features that need toast feedback on write operations (006, 010, etc.); all future forms that will surface help via the corpus
- **US3 depends on Slab C foundation**: T024 (`HelpPopover`) must be implemented after T036–T043 (corpus types, manifest, `useHelp`, `HelpDrawer`) are complete.
- **No backend changes**: 004 is pure frontend + dev tooling. No new endpoints, no schema changes.
