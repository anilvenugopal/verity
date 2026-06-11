# Tasks: Shell Polish + Dev Environment Hardening

**Feature**: `004-shell-polish` · **Plan**: [plan.md](plan.md) · **Spec**: [spec.md](spec.md)

No backend changes. No schema changes. All work is `hub/portal/` + `tools/dev.py` + config files.

**Slab A** (user-facing): toast system → wiring into write paths → error states → help popover.
**Slab B** (developer-facing): venv/node discipline → dev test commands → portal unit tests.

---

## Phase 1: Setup

- [X] T001 Commit `.vscode/settings.json` created in session (Python interpreter, pytest cwd, Vitest config, Pylance extraPaths) — file already exists at `.vscode/settings.json`
- [X] T002 Create `hub/.python-version` containing `3.14` so uv and pyenv-compatible tools always activate the correct interpreter
- [X] T003 [P] Add `.nvmrc` at `hub/portal/.nvmrc` containing `24`; add `"engines": { "node": ">=24" }` to `hub/portal/package.json`
- [X] T004 [P] Add `pytest-cov` to `[project.optional-dependencies] dev` in `hub/pyproject.toml`; add `[tool.coverage.run]` (`source = ["verity.hub"]`) and `[tool.coverage.report]` (`fail_under = 70`, `show_missing = true`) sections; run `uv sync` to update lockfile
- [X] T005 [P] Add `@testing-library/react`, `@testing-library/jest-dom`, `@testing-library/user-event` as dev deps in `hub/portal/package.json`; run `npm install`

**Checkpoint**: config files in place; both package managers synced.

---

## Phase 2: Foundational — Toast system (blocks all Slab-A wiring)

**Goal**: A working toast primitive that any module can call. The wiring tasks in US1 depend on this being complete.

**Independent test**: Import `useToast` in a test component, call `toast('hello', 'success')`, confirm a `.toast` element appears and auto-removes after 4 s.

- [X] T006 Create `hub/portal/src/shell/ToastContext.tsx`: `ToastContext` + `ToastProvider` using `useReducer`; actions `ADD_TOAST` / `REMOVE_TOAST`; each toast has `id` (monotonic counter), `message`, `tone` (`success|warning|error|info`), `autoDismiss` (default `true`); export `useToastDispatch()` internal hook
- [X] T007 Create `hub/portal/src/shell/useToast.ts`: exports `useToast()` returning `{ toast(message, tone?, autoDismiss?) }` convenience wrapper over `useToastDispatch`; also export a module-level `toastEmitter` singleton so `api/client.ts` (non-component) can fire toasts without the hook
- [X] T008 Create `hub/portal/src/shell/Toast.tsx`: renders the toast stack (absolute-positioned, top-right); each item shows tone icon + message + dismiss button; CSS transition for enter/exit; auto-dismiss via `useEffect` timeout
- [X] T009 Create `hub/portal/src/styles/toast.css`: toast stack positioning, per-tone colour tokens (reuse kit `--color-*` vars), enter/exit animation; import in `hub/portal/src/styles/index.css` (or equivalent global import)
- [X] T010 Mount `<ToastProvider>` wrapping the router and `<Toast />` inside it in `hub/portal/src/App.tsx`
- [X] T011 Wire `toastEmitter` into `hub/portal/src/api/client.ts` error interceptor: 4xx responses fire `toast(detail ?? 'Request failed', 'error', false)` (no auto-dismiss); 5xx fire `toast('Server error — try again', 'error', false)`; network errors (fetch throws) fire `toast('Network error — check your connection', 'error', false)`; 2xx responses do NOT fire toasts (callers handle success)

**Checkpoint**: Toast renders and dismisses. API errors surface automatically. No call site needs to handle toasts for network/server failures.

---

## Phase 3: US1 — Wire toast into all existing write paths

**Goal**: Every form submit, approval action, and data mutation in the portal gives the user feedback.

**Independent test**: Open each write path below; confirm spinner appears if response takes >300ms and a toast appears on completion or error. All existing operations must be unchanged in behaviour — only feedback is added.

- [X] T012 [US1] `hub/portal/src/pages/applications/ApplicationForm.tsx` (or equivalent onboard submit): wrap the submit call with a 300ms spinner guard; on success fire `toast('Application submitted', 'success')`
- [X] T013 [US1] `hub/portal/src/pages/applications/ApplicationWorkspace.tsx` — approval signoff action: `toast('Signed off', 'success')` on approve; `toast('Sign-off recorded', 'info')` on other decisions
- [X] T014 [US1] `hub/portal/src/pages/intakes/IntakeDetail.tsx` — submit-for-approval: `toast('Submitted for approval', 'success')`; intake signoff: `toast('Signed off', 'success')`; change-proposal raise: `toast('Change proposal raised', 'success')`; change-proposal signoff: `toast('Signed off', 'success')`
- [X] T015 [US1] `hub/portal/src/pages/intakes/AssessmentForm.tsx` — assessment save: `toast('Assessment saved', 'success')` on success
- [X] T016 [US1] `hub/portal/src/pages/intakes/RiskObligations.tsx` — evidence record: `toast('Evidence recorded', 'success')`; exception raise: `toast('Exception raised', 'success')`; exception signoff: `toast('Exception approved/rejected', 'success')`; asset link: `toast('Asset linked', 'success')`
- [X] T017 [US1] `hub/portal/src/pages/registry/RegistryList.tsx` — asset create: `toast('Asset created', 'success')`; version create: `toast('Version created', 'success')`; lifecycle advance: `toast('Stage advanced', 'success')`
- [X] T018 [US1] Spinner utility: create `hub/portal/src/shell/useBusyToast.ts` — a hook wrapping a write call: starts a local `busy` state, after 300ms sets a spinner indicator, resolves on completion; used by T012–T017 to replace existing ad-hoc `setBusy` patterns where present

**Checkpoint**: All write paths give visible feedback. Open the browser Network tab, throttle to Slow 3G, and exercise each path.

---

## Phase 4: US2 — Error states (404 / 403 / error boundary)

**Goal**: The portal never shows a blank page or a raw JS crash. Every error condition has a recovery screen.

**Independent test**: (a) Navigate to `/intakes/00000000-0000-0000-0000-000000000000` → 404 screen, not blank. (b) Force a 403 via DevTools → 403 screen. (c) Throw inside a component via browser console → error boundary screen with ID.

- [X] T019 [US2] Create `hub/portal/src/shell/AppErrorBoundary.tsx`: React class component wrapping the router; `componentDidCatch` logs the error + a client-generated ID (monotonic counter); renders `ErrorScreen` with the ID and a reload button; import and wrap in `App.tsx`
- [X] T020 [US2] Create `hub/portal/src/shell/ErrorScreen.tsx`: reusable screen component accepting `title`, `detail`, `id?`, `action?` (button label + callback); used by AppErrorBoundary, 404, and 403
- [X] T021 [US2] Add React Router `errorElement` to the root route in `hub/portal/src/App.tsx`: use `useRouteError()` to detect 404 vs other errors; render `<ErrorScreen title="Page not found" ...>` for 404, `<ErrorScreen title="Something went wrong" ...>` for others
- [X] T022 [US2] Add a `*` catch-all route at the end of the router in `hub/portal/src/App.tsx` rendering `<ErrorScreen title="Page not found" detail="This page doesn't exist." action={{ label: 'Go home', to: '/' }} />`
- [X] T023 [US2] Handle 403 in `hub/portal/src/api/client.ts`: on 403 response navigate to `/forbidden` (use a module-level navigator ref set in `App.tsx`); add `/forbidden` route rendering `<ErrorScreen title="Access denied" detail="You don't have permission to view this." action={{ label: 'Go home', to: '/' }} />`

**Checkpoint**: Bad UUID → 404 screen. Forbidden API call → 403 screen. `throw new Error('test')` in a component → error boundary screen.

---

## Phase 5: US6 — Help Corpus Foundation (blocks US3)

**Goal**: Establish the help corpus architecture: types, manifest, `useHelp` hook, `HelpDrawer`, and initial content. US3 depends on this being complete so `HelpPopover` can resolve content from the corpus instead of inline props.

**Independent test**: `import { useHelp } from '@/help/useHelp'` in a test; call `useHelp('forms.assessment.fields.decision_type')` — returns the `FieldDef` from `assessmentCatalog.ts`. Call `useHelpPage('forms.assessment')` — returns a function. Call it — returns an HTML string.

### US6-A · Structure, types, manifest, hooks (foundation — required for US3)

- [X] T036 [US6] Create `hub/portal/src/help/types.ts`: export `HelpSnippet` (identical shape to `FieldDef`), `WorkflowStep`, `HelpPageLoader`, `FormHelp`, `WorkflowHelp`, `RoleHelp`; export `type FieldDef = HelpSnippet` alias so `assessmentCatalog.ts` remains unchanged
- [X] T037 [US6] Create `hub/portal/src/help/forms/assessment/fields.ts`: re-export `FIELDS` from `assessmentCatalog.ts` as the default export conforming to `Record<string, HelpSnippet>`; create `hub/portal/src/help/forms/assessment/_page.html` with a structured help page for the assessment form (see C7 format in spec)
- [X] T038 [US6] [P] Create `fields.ts` + `_page.html` for the remaining six forms: `intake-create`, `application-onboard`, `evidence-record`, `exception-raise`, `change-proposal`, `registry-asset` — populate with field snippets matching the actual form fields in the portal; HTML pages follow the C7 format
- [X] T039 [US6] [P] Create `steps.ts` + `_page.html` for the three workflows: `intake-approval`, `registry-promotion`, `obligation-resolution`; create role help pages: `roles/_overview.html`, `roles/underwriter.html`, `roles/compliance-officer.html`, `roles/risk-manager.html`; create how-to pages: `how-to/_index.ts`, `how-to/submit-intake.html`, `how-to/resolve-obligations.html`, `how-to/advance-registry-asset.html`, `how-to/raise-change-proposal.html`; create `overview/product.html` + `overview/glossary.html`
- [X] T040 [US6] Create `hub/portal/src/help/_manifest.ts`: typed manifest with lazy `?raw` imports for all HTML pages; static imports for all `fields.ts` and `steps.ts`; export `helpManifest as const` (see C4 in spec for the shape)
- [X] T041 [US6] Create `hub/portal/src/help/useHelp.ts`: export `useHelp(path: string): HelpSnippet | null` and `useHelpPage(path: string): HelpPageLoader | null`; path is dot-separated (`'forms.assessment.fields.decision_type'`); walks `helpManifest` — returns `null` for unknown paths rather than throwing
- [X] T042 [US6] Create `hub/portal/src/shell/HelpDrawer.tsx`: renders help page HTML in the existing `.modal/.overlay` shell; driven by a module-level `helpDrawer` singleton (`open(path)` / `close()`); mounts once in `App.tsx`; add a `/help/:path*` route that calls `helpDrawer.open(path)` on mount (deep-link support)
- [X] T043 [US6] Create `hub/portal/src/styles/help.css`: styles for `.help-page`, `.help-page__header`, `.help-page__section`, `.help-page__fields dl/dt/dd`; import in `hub/portal/src/styles/index.css`

### US6-B · Toast integration (addendum to A1 — T006–T008 already done)

- [X] T044 [US6] Extend the existing toast system: add optional `helpId?: string` to the `toast()` call signature in `useToast.ts` and the `ADD_TOAST` action in `ToastContext.tsx`; update `Toast.tsx` to render a "Learn more →" `<button>` inside the toast when `helpId` is present — the button calls `helpDrawer.open(helpId)`. No change to any existing call site.

### US6-C · Manifest validation test

- [X] T045 [US6] Create `hub/portal/src/help/__tests__/manifest.test.ts`: (a) every `helpManifest.forms[*].fields[*]` entry has a non-empty `label` and `help` string; (b) every page loader is a function; (c) `useHelp('forms.assessment.fields.decision_type')` returns the correct label. No DOM, pure data.

**Checkpoint**: `tsc --noEmit` clean. `useHelp('forms.assessment.fields.decision_type')` returns the `decision_type` entry. `helpDrawer.open('forms.assessment')` renders the assessment help page in the drawer. All manifest validation tests pass.

---

## Phase 5.5: US3 — Contextual help popover *(depends on Phase 5 complete)*

**Goal**: Assessment form fields have a corpus-backed `?` affordance. Establishes `HelpPopover` as the lightweight popover component for non-`FieldHelp` contexts (section headers, page titles, workflow steps).

**Independent test**: Open an intake detail → Assessment tab → click `?` next to "Decision type" → popover shows `decision_type.help` text from the corpus. Click "Learn more →" → `HelpDrawer` opens with the full assessment form help page. Press `Escape` → closes.

- [X] T046 [US3] Create `hub/portal/src/shell/HelpPopover.tsx`: renders a `?` button using the native Popover API (`popovertarget` / `<div popover>`); accepts `helpId: string`; calls `useHelp(helpId)` to get the snippet; shows `snippet.help` in the popover body; renders a "Learn more →" button that calls `helpDrawer.open(helpId.split('.fields.')[0])` when `snippet.why` is present (i.e. there is a full page to navigate to). No inline content props — all content from corpus.
- [X] T047 [US3] Wire `HelpPopover` into `hub/portal/src/pages/intakes/AssessmentForm.tsx` section headers: each section (`Decision context`, `Data & training`, `Human oversight`, `Risk`, `Fairness`) gets a `<HelpPopover helpId="forms.assessment.fields.<first-field-in-section>" />` next to the section heading, giving a section-level entry point into the corpus. Individual field labels continue to use the existing `FieldHelp` component — `HelpPopover` is additive at the section level.

**Checkpoint**: `?` appears at each assessment section header. Click opens native popover. "Learn more →" opens `HelpDrawer` with the assessment help page. `FieldHelp` field-level tooltips are unchanged.

---

## Phase 6: US4 — Dev test commands

**Goal**: `python tools/dev.py test` and `python tools/dev.py test:portal` are the canonical way to run tests. Both print which interpreter they are using.

**Independent test**: Run `python tools/dev.py test` from repo root → see "Using: hub/.venv/bin/python (3.14.x)" → all 67 pytest tests pass. Run `python tools/dev.py test:portal` → see "Using: node vX.Y.Z" → Vitest runs (0 failures).

- [X] T026 [US4] Add `test` subcommand to `tools/dev.py`: runs `uv run pytest` from `hub/` using `_hub_env()` env dict; prints interpreter path before running (`hub/.venv/bin/python --version`); passes `--tb=short` by default; accepts `--cov` flag to add `--cov=verity.hub --cov-report=term-missing`
- [X] T027 [US4] Add `test:portal` subcommand to `tools/dev.py`: `npm run test` from `hub/portal/`; prints `node --version` before running; streams output

**Checkpoint**: Both commands work from repo root, print interpreter, and stream output.

---

## Phase 7: US5 — Portal unit tests

**Goal**: At least 3 passing Vitest tests visible in the VSCode Testing tab, covering the two areas where bugs have already been found plus the API error path.

**Independent test**: Run `npm run test` from `hub/portal/` → all tests pass. Open VSCode Testing tab → Vitest tree shows the tests.

- [X] T028 [US5] Create `hub/portal/src/shell/__tests__/nav.test.ts`: tests for `resolveNav` — (a) gates hidden when `can()` returns false, (b) children resolved recursively, (c) `ownedPaths` present on the intake app entry, (d) postProcess re-gates injected nodes. Pure function, no DOM, no mocks.
- [X] T029 [US5] Create `hub/portal/src/pages/intakes/__tests__/assessmentCatalog.test.ts`: (a) every key used in `AssessmentForm.tsx`'s `sel()` / `bool()` / `txt()` calls exists in `FIELDS` — this is the test that would have caught the `classification` crash; (b) every entry with `options` has at least one option with a non-empty `value` and `label`. No DOM.
- [X] T030 [P] [US5] Create `hub/portal/src/shell/__tests__/Toast.test.tsx`: render `<ToastProvider><Toast /></ToastProvider>`, fire a toast via `useToast()`, assert the message appears; fire dismiss, assert it disappears. Uses `@testing-library/react`.

**Checkpoint**: `npm run test` → 3+ tests pass. VSCode Testing tab → Vitest tree visible with tests.

---

## Phase 8: Polish & cross-cutting

- [X] T031 [P] Write `hub/docs/dev-setup.md`: covers (a) Python — always `uv run` from `hub/`; never `pip install`; never `python -m pytest` from root; (b) Node — `nvm use` from `hub/portal/`; (c) VSCode — open workspace from repo root, Testing tab will auto-discover both suites; (d) `./dev test` and `./dev test:portal`; (e) the `noUncheckedIndexedAccess` rule and why reverting it is forbidden
- [ ] T032 Verify VSCode Testing tab end-to-end: open repo in VSCode, confirm Python Testing shows 67 pytest tests and Vitest shows 3+ tests; run all → all pass; record any setup steps needed in `dev-setup.md`
- [X] T033 [P] Run `tsc --noEmit` and `vite build` from `hub/portal/` — confirm clean
- [X] T034 [P] Run `python tools/dev.py test --cov` — confirm ≥70% coverage threshold passes
- [X] T035 Mark completed tasks `[X]`; update `CLAUDE.md` shipped status for 004

---

## Dependencies & Execution Order

- **Phase 1 (Setup)**: No dependencies — all T001–T005 can run in parallel immediately.
- **Phase 2 (Toast foundation)**: Requires T005 (dev deps installed). T006–T009 parallelisable; T010 requires T006–T008; T011 requires T007.
- **Phase 3 (US1 wiring)**: Requires Phase 2 complete (toast primitive must exist). T012–T017 parallelisable across files; T018 can run alongside.
- **Phase 4 (US2 errors)**: Independent of Phase 3 — can run in parallel with US1 wiring after Phase 2.
- **Phase 5 (US6 corpus foundation)**: Independent of US1/US2/US3. T036–T037 first (types + assessment re-export); T038–T039 [P] content population (can run in parallel with T040–T043); T040 requires T036–T039; T041 requires T040; T042 requires T041; T043 requires T041. T044 (toast helpId) requires T042 (HelpDrawer singleton must exist). T045 requires T040–T042.
- **Phase 5.5 (US3 help)**: Requires Phase 5 complete (T036–T042 must exist). T046 requires T041 + T042; T047 requires T046.
- **Phase 6 (US4 dev commands)**: Independent of all portal work — pure `tools/dev.py` change. Can start after T004.
- **Phase 7 (US5 tests)**: T028/T029 independent; T030 requires Phase 2 complete (Toast component exists); T045 counted here.
- **Phase 8 (Polish)**: Requires all previous phases.

### Parallel opportunities

After Phase 1 + 2:
- US1 wiring (T012–T018) ∥ US2 error states (T019–T023) ∥ US6 corpus (T036–T045) ∥ US4 dev commands (T026–T027) ∥ US5 tests T028/T029
- US3 (T046–T047) after US6 corpus is complete

### Key sequencing rule

US3 (T046–T047) is **blocked** until Phase 5 (T036–T043) is complete. Do not start T046 until `HelpDrawer`, `useHelp`, and `_manifest.ts` all exist and compile.

---

## Implementation Strategy

**MVP (Slab A first)**: Phase 1 → Phase 2 (toast foundation) → Phase 3 (wire all write paths) → Phase 4 (error states). At this point the portal is production-quality for user-facing feedback. Demo-ready.

**Then Slab C (corpus) + Slab B (dev tooling) in parallel**: Phase 5 (corpus foundation T036–T045) ∥ Phase 6 (dev commands T026–T027). Phase 5.5 (US3, T046–T047) after corpus is done. Phase 7 (portal tests) after corpus. Phase 8 (polish) last.

**Content population (T038–T039)** is the most effort-intensive part of Slab C. These tasks are [P] — they can be authored incrementally after the foundation ships, as long as the `_page.html` files exist (even as stubs) so the `?raw` imports don't break the build. Stub format: `<article class="help-page"><h1>…</h1><p>Coming soon.</p></article>`.
