# Implementation Plan: Studio — Authoring Canvas

**Branch**: `006-studio-ui` | **Date**: 2026-06-13 | **Spec**: [spec.md](./spec.md)

## Summary

Feature 006 delivers three authoring surfaces in the registry portal — a three-panel Studio canvas for composing agent/task versions, a block editor for authoring prompt versions, and a diff viewer for comparing two prompt version block sequences. All three are React/TypeScript; no new backend endpoints, schema changes, or migrations are required. Data access uses the 005 registry API exclusively.

## Technical Context

**Language/Version**: TypeScript 5 (React 18, Vite 5)

**Primary Dependencies**: React Router v6 (already in portal), existing Verity design system CSS, `@/api/client`, `@/shell/useToast` — all present

**Storage**: None (no new DB work); client-side in-memory state only

**Testing**: Vitest (already configured); new unit tests for LCS algorithm and block compile

**Target Platform**: Browser (same portal at `hub/portal/`)

**Project Type**: React single-page application — new pages within existing registry section

**Performance Goals**: Studio canvas renders in < 200ms; diff viewer computes LCS in < 50ms for sequences up to 50 blocks (well within any realistic prompt)

**Constraints**: No new npm dependencies unless strictly necessary. No backend changes (SC-005). Must pass `vite build` clean and all existing Vitest tests.

**Scale/Scope**: Three new page components + shared sub-components + one utility module. Adds routes under `/registry/agents/:id/versions/:vid/studio`, `/registry/tasks/:id/versions/:vid/studio`, `/registry/prompts/:id/versions/:vid/edit`, `/registry/prompts/:id/diff`.

## Constitution Check

*GATE: Must pass before Phase 0 research. Re-check after Phase 1 design.*

| Principle | Assessment | Notes |
|-----------|-----------|-------|
| I. Spec Precedes Implementation | **PASS** | Spec written and quality-checked; this plan is the required precursor |
| II. Schema Is the Hardened Foundation | **PASS** | No schema changes; no migrations; read-only from existing 005 API |
| III. Legacy Is Reference, Never Source | **PASS** | Reference designs (`verity-agent-studio.html`, `prompt-editor-v2.jsx`, `prompt_editor_diff_v14_v150.html`) inform UI patterns only; no code copied |
| IV. API-Only Governance Boundary | **PASS** | All data through hub API; no direct DB access from portal |
| V. Uniform Bindings, Agent-Only Tools | **PASS** | Tools tab absent on task Studio pages (FR-ST-005); spec enforces this |
| VI. Equity-Research Slice First | **PASS** | Feature 006 is the Wave 2 UI milestone; roadmap sequencing satisfied |
| VII. Governed Deployment | **PASS** | Frontend only; no packaging/deployment changes |
| VIII. Continuous Compliance | **N/A** | Authoring UI; no compliance enforcement controls in scope |

**Post-design re-check**: Re-evaluate after Phase 1 when file structure and route additions are finalised; no violations anticipated.

## Project Structure

### Documentation (this feature)

```text
specs/006-studio-ui/
├── plan.md              # This file
├── research.md          # Phase 0 output
├── data-model.md        # Phase 1 output
├── quickstart.md        # Phase 1 output
└── tasks.md             # Phase 2 output (/speckit-tasks — NOT created by /speckit-plan)
```

### Source Code

All new code lives under the existing portal. No new top-level directories.

```text
hub/portal/src/
├── pages/registry/
│   ├── studio/                            # NEW — all Studio surfaces
│   │   ├── StudioCanvas.tsx               # Three-panel compose canvas (US1)
│   │   ├── StudioCanvas.css              # Panel layout + drag-handle styles
│   │   ├── LibraryPanel.tsx              # Left panel: Prompts/Tools search tabs
│   │   ├── CompositionPanel.tsx          # Centre panel: manifest rows + assignment forms
│   │   ├── PropertiesPanel.tsx           # Right panel: version metadata + focused item
│   │   ├── BlockEditor.tsx               # Prompt block editor page (US2)
│   │   ├── BlockEditor.css              # Block row + toolbar + preview pane styles
│   │   ├── BlockForm.tsx                # Inline add/edit form per block kind
│   │   ├── BlockRenderer.tsx            # Read-only single-block renderer (reused in editor + diff)
│   │   ├── PromptDiff.tsx               # Diff viewer page (US3)
│   │   ├── PromptDiff.css              # Diff status colours + left-rail navigator styles
│   │   └── lcs.ts                      # LCS algorithm + diff entry computation
│   ├── agents/
│   │   ├── AgentVersionDetail.tsx       # MODIFIED: add "Open in Studio" button
│   │   └── ...
│   ├── tasks/
│   │   ├── TaskVersionDetail.tsx        # MODIFIED: add "Open in Studio" button
│   │   └── ...
│   └── prompts/
│       ├── PromptDetail.tsx             # MODIFIED: add "Compare versions" button
│       ├── PromptVersionDetail.tsx      # MODIFIED: add "Edit blocks" action on latest version card
│       └── ...
└── App.tsx                              # MODIFIED: add four new routes
```

## Phase 0: Research Findings

*(All technical questions resolved analytically — no external research agents required.)*

### Finding 1 — LCS algorithm for block diff

**Decision**: Implement a standard O(mn) LCS on block sequences, comparing by `(kind, serialised content)` equality. Blocks with ephemeral local `id` fields are excluded from equality. Output is a sequence of `DiffEntry` objects `{ block, status: 'added' | 'removed' | 'unchanged' }`.

**Rationale**: Prompt sequences are short (< 50 blocks in practice); O(mn) is imperceptible. No external library needed — the algorithm fits in ~40 lines. This avoids adding a dependency.

**Implementation location**: `studio/lcs.ts`, exported as `computeDiff(base: PromptBlock[], head: PromptBlock[]): DiffEntry[]`.

**Block equality**: `blocksEqual(a, b)` — compare `a.kind === b.kind`, then kind-specific content field equality (deep equality for arrays/objects, strict equality for primitives). The ephemeral `id` field is NOT compared.

---

### Finding 2 — Panel resize (drag handles)

**Decision**: CSS `grid-template-columns` with a CSS custom property `--lib-w` (default 220px) and `--props-w` (default 280px); drag handles update the custom property via `document.documentElement.style.setProperty` on `mousemove`. Clamp to min 140px / max 400px per panel.

**Rationale**: No external library needed. Grid with custom properties is reliable and GPU-composited. React state is not used for drag (avoids re-renders during drag); the CSS property updates are direct DOM mutations in the event handler.

---

### Finding 3 — Client-side compile_blocks

**Decision**: Reimplement `compile_blocks` in TypeScript in `lcs.ts` (alongside diff utility) as a pure function mirroring the backend's logic:
- prose → `block.text`
- var → `{block.name}`
- list → numbered items joined by `\n`
- table → markdown table rows
- code → fenced code block

**Rationale**: The compiled preview (FR-ST-014) must update live as the developer edits. Making an API call on every keystroke is unnecessary. The backend's `compile_blocks` logic is simple and documented in the discriminated union spec; keeping client and server in sync is low risk given the deterministic algorithm.

---

### Finding 4 — Semver entry dialog

**Decision**: Use a native `<dialog>` element (same pattern as the confirmation dialogs in existing pages). No new component library needed. Validate with regex `^\d+\.\d+\.\d+(-[\w.]+)?(\+[\w.]+)?$` before submission; show inline error if invalid.

**Rationale**: The existing portal uses native `popover` API for help; native `dialog` is the same pattern, consistent, and already widely supported.

---

### Finding 5 — Latest version detection for read-only mode

**Decision**: `PromptVersionDetail` already receives `prompt_version_id`. The block editor determines whether a version is the latest by comparing `prompt_version_id` against the `latest_version_id` from the parent `PromptSummary`, fetched via `GET /api/registry/prompts/:id`. If they match, editor is editable; otherwise read-only.

**Rationale**: The backend returns `latest_version_id` on `PromptSummary`; no additional API endpoint needed.

---

### Finding 6 — No new API contracts required

The Studio canvas, block editor, and diff viewer call only existing 005 registry endpoints:

| Operation | Endpoint | Existing? |
|-----------|----------|-----------|
| List prompts (for Library) | `GET /api/registry/prompts?application_id=` | Yes |
| List tools (for Library) | `GET /api/registry/tools?application_id=` | Yes |
| Get prompt version blocks | `GET /api/registry/prompt-versions/:vid` | Yes |
| Create prompt version | `POST /api/registry/prompts/:id/versions` | Yes |
| Add prompt assignment | `POST /api/registry/versions/:vid/prompt-assignments` | Yes |
| Remove prompt assignment | `DELETE /api/registry/versions/:vid/prompt-assignments/:pvid/:role` | Yes |
| Add tool assignment | `POST /api/registry/versions/:vid/tool-assignments` | Yes |
| Remove tool assignment | `DELETE /api/registry/versions/:vid/tool-assignments/:tvid` | Yes |
| Get executable version | `GET /api/versions/:vid` | Yes |

No new `contracts/` file is required — the existing `contracts/registry-api.yaml` (from 005) covers all of these.

---

## Phase 1: Design

### Data Model

*(see `data-model.md`)*

Client-side state entities for each surface:

**Studio Canvas session state** (held in `StudioCanvas.tsx` — cleared on unmount):
```
{
  version: ExecutableVersion
  prompts: PromptAssignment[]
  tools: ToolAssignment[]          // empty array for task versions
  libraryPrompts: PromptSummary[]
  libraryTools: ToolSummary[]      // not fetched for task versions
  selectedLibraryItem: { kind: 'prompt' | 'tool'; id: string } | null
  assignForm: { open: boolean; kind: 'prompt' | 'tool'; targetId: string }
}
```

**Block editor state** (held in `BlockEditor.tsx` — cleared on unmount):
```
{
  prompt: PromptSummary
  sourceVersion: PromptVersionDetail   // loaded from DB; blocks copied to editBlocks
  editBlocks: EditBlock[]             // in-memory mutable copy
  isReadOnly: boolean                  // true if sourceVersion.id !== prompt.latest_version_id
  semverDialogOpen: boolean
  semverInput: string
  semverError: string | null
}

EditBlock = PromptBlock & { _localId: string }  // localId for React key; NOT sent to backend
```

**Diff viewer state** (held in `PromptDiff.tsx`):
```
{
  prompt: PromptSummary
  versions: PromptVersionSummary[]
  baseVid: string
  headVid: string
  baseBlocks: PromptBlock[] | null
  headBlocks: PromptBlock[] | null
  diffEntries: DiffEntry[]            // computed client-side via lcs.ts
}

DiffEntry = { block: PromptBlock; status: 'added' | 'removed' | 'unchanged' }
```

### Implementation Phases

#### Phase 1 — Shared utilities + block primitives

Build the foundation shared across all three surfaces:
- `lcs.ts`: `blocksEqual()`, `computeDiff()`, `compileBlocks()` pure functions
- `BlockRenderer.tsx`: read-only render of a single `PromptBlock` by kind (used in editor + diff)
- Vitest unit tests for `lcs.ts` covering: LCS correctness, blocksEqual, compileBlocks for all 5 kinds

#### Phase 2 — Studio canvas (US1, P1)

Route: `/registry/agents/:id/versions/:vid/studio` and `/registry/tasks/:id/versions/:vid/studio`

Build order (sequential, each depends on the prior):
1. `StudioCanvas.css` — three-panel grid layout with CSS custom properties for widths, drag-handle rules
2. `LibraryPanel.tsx` — fetches `GET /api/registry/prompts?application_id=...` and `/api/registry/tools?application_id=...`; Prompts/Tools tabs + search; emits `onSelect` callback
3. `CompositionPanel.tsx` — receives `prompts`, `tools`, `kind` props; renders prompt assignments grouped by api_role; tool assignments section suppressed when `kind === 'task'`; assignment forms (inline form for role + ordinal for prompts; confirm-button for tools); remove buttons
4. `PropertiesPanel.tsx` — receives `version` + `selectedLibraryItem`; shows version metadata; shows library item summary when focused
5. `StudioCanvas.tsx` — top-level page component; owns session state; wires panels; drag-handle event listeners; "Open in Studio" navigation target
6. `AgentVersionDetail.tsx` + `TaskVersionDetail.tsx`: add "Open in Studio" navigation button (no other changes)
7. `App.tsx`: add two new routes

#### Phase 3 — Block editor (US2, P2)

Route: `/registry/prompts/:id/versions/:vid/edit`

Build order:
1. `BlockEditor.css` — toolbar strip, block-row with action strip, compiled-preview pane
2. `BlockForm.tsx` — five kind-specific inline forms (prose: textarea; var: name/type/desc/eg/opts/req fields; list: multi-line textarea split by newline; table: dynamic rows/cols; code: lang select + textarea)
3. `BlockEditor.tsx` — page component owning edit state; block reorder (up/down); delete with confirmation; add block via toolbar + BlockForm; live compiled preview via `compileBlocks(editBlocks)`; semver dialog; POST on save
4. `PromptVersionDetail.tsx` + `PromptDetail.tsx`: wire "Edit blocks" navigation to latest version; read-only notice on non-latest

#### Phase 4 — Diff viewer (US3, P3)

Route: `/registry/prompts/:id/diff`

Build order:
1. `PromptDiff.css` — added/removed/unchanged colour system, left-rail navigator, diff toolbar
2. `PromptDiff.tsx` — page component; version selectors; fetches both versions' blocks; `computeDiff()` call; renders `DiffEntry[]` with `BlockRenderer` + status badge; left-rail with jump-scroll; diff stat line; base/head swap
3. `PromptDetail.tsx`: add "Compare versions" button; disable when `version_count < 2` with tooltip

#### Phase 5 — Validation

- Run `vite build` — must be clean
- Run `./dev test:portal` — all existing Vitest tests must pass + new lcs.ts unit tests pass
- Run `./dev test` — all 67+ pytest pass (no backend changes to break)
- Manual smoke: Studio canvas → assign prompt → assign tool → remove one → toast visible; Block editor → add VarBlock → save as 0.0.2 → new version in list; Diff viewer → compare v1 to v2 → LCS correct

### Entry-point wiring summary

| Existing page | Change |
|---------------|--------|
| `AgentVersionDetail.tsx` | Add "Open in Studio" button → `/registry/agents/:id/versions/:vid/studio` |
| `TaskVersionDetail.tsx` | Add "Open in Studio" button → `/registry/tasks/:id/versions/:vid/studio` |
| `PromptVersionDetail.tsx` | Add "Edit blocks" button on latest version card → `/registry/prompts/:id/versions/:vid/edit` |
| `PromptDetail.tsx` | Add "Compare versions" button → `/registry/prompts/:id/diff`; disable when `version_count < 2` |
| `App.tsx` | Add four new `<Route>` entries under `/registry` |

No other files are modified.
