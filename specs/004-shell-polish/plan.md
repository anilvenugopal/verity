# Implementation Plan: Shell Polish + Dev Environment Hardening

**Branch**: `004-shell-polish` | **Date**: 2026-06-11 | **Spec**: [spec.md](spec.md)

## Summary

Two complementary slabs with a shared goal — confidence. **Slab A** (user-facing): wire transient toast feedback into every write path, add a contextual help popover pattern, and add error boundary + 404/403 screens so the portal never shows a blank page. **Slab B** (developer-facing): enforce Python venv discipline, pin Node, wire VSCode Testing tab for both Python and TypeScript, add `dev test` commands, write the first portal unit tests, and set a coverage floor.

No new backend endpoints. No schema changes. Everything is `hub/portal/` + `tools/dev.py` + `.vscode/` + `hub/` config files.

---

## Technical Context

**Language/Version**: TypeScript 5 + React 18 (portal); Python 3.14 (hub dev tooling)

**Primary Dependencies (portal)**: Vite 5, React Router, existing CSS kit (`hub/portal/src/styles/`); Vitest + `@testing-library/react` for unit tests (new dev dep)

**Storage**: None — 004 has no DB changes

**Testing**: Vitest (portal unit tests); pytest via `uv run` (Python)

**Target Platform**: Browser (portal); developer workstation (dev tooling)

**Project Type**: Web application frontend + dev tooling scripts

**Performance Goals**: Toast renders within one animation frame of the triggering event; no noticeable layout shift

**Constraints**: Toast component must not introduce a new CSS layer or break existing kit layout; must work without a global state library (use a simple event-emitter or React context)

**Scale/Scope**: ~8 portal components touched for toast wiring; ~3–5 new test files; ~50 lines in `tools/dev.py`

---

## Constitution Check

*GATE: Must pass before Phase 0 research. Re-checked after Phase 1 design.*

| Principle | Status | Notes |
|-----------|--------|-------|
| I. Spec precedes implementation | ✅ PASS | This plan document is the spec artifact |
| II. Schema is hardened foundation | ✅ PASS | No schema changes in this feature |
| III. Legacy is reference, never source | ✅ PASS | No legacy imports |
| IV. API-only governance boundary | ✅ PASS | No cross-component dependency changes |
| V. Uniform bindings, agent-only tools | N/A | No agent/task changes |
| VI. Equity-research slice / parity | N/A | UI shell work, not feature-parity |
| VII. Governed deployment / reproducibility | ✅ PASS | Dev tooling improvements reinforce reproducibility |
| VIII. Continuous compliance | N/A | No compliance controls in this feature |

**Development workflow gates**:
- Spec gate: ✅ spec.md written and reviewed
- Schema gate: N/A
- Compliance gate: N/A
- Sequencing: 004 depends on 002 (portal scaffold) and 003 (write paths to wire). Both shipped. ✅

**No violations.**

---

## Research (Phase 0)

All decisions resolved without external research — the tech stack is fixed and the patterns are well-established.

### R1 · Toast implementation pattern

**Decision**: React context + `useReducer` for toast state; a singleton `toast()` helper function that dispatches into the context so any module (including non-component code like `api/client.ts`) can fire a toast without prop-drilling.

**Why**: The portal already uses React context for session state. Adding a `ToastContext` is consistent. The alternative (a global event emitter outside React) would work but is less idiomatic and harder to test.

**Pattern**:
```
hub/portal/src/shell/
  ToastContext.tsx     — context + provider + useReducer
  useToast.ts          — hook: returns { toast } helper
  Toast.tsx            — renders the toast stack; mounted once in App.tsx
  toast.css            — scoped styles (not in components.css — see CSS architecture)
```

The `api/client.ts` error interceptor calls `toast()` directly for 4xx/5xx and network errors so individual call sites don't need to handle errors they don't own.

### R2 · Help popover pattern

**Decision**: CSS-only popover using the native `popover` API (supported in all modern browsers) with a `<button popovertarget>` trigger. No JS required for open/close. Content is a prop passed to a `HelpPopover` component.

**Why**: The native popover API avoids a floating-UI dependency and is already in the browser. The alternative (a custom `useState`-based show/hide) would need click-outside handling; the native API handles that for free.

### R3 · Error boundary

**Decision**: A single `AppErrorBoundary` class component wrapping the router in `App.tsx`. On catch: renders an error screen with a client-generated ID (monotonic counter, not `crypto.randomUUID` — must work without HTTPS). React Router's `errorElement` handles route-level 404/403; the class boundary catches unexpected JS errors.

**Why**: React Router v6 `errorElement` is the correct tool for route errors (404, loader throws). A class `ErrorBoundary` is the correct tool for unexpected render-phase JS errors. They cover different failure modes and are complementary.

### R4 · Vitest + Testing Library

**Decision**: Add `@testing-library/react` and `@testing-library/jest-dom` as dev deps. Tests live in `src/**/__tests__/*.test.ts(x)`. First test file: `src/shell/__tests__/nav.test.ts` (pure function, no DOM — proves Vitest works). Second: `src/pages/intakes/__tests__/assessmentCatalog.test.ts` (proves `noUncheckedIndexedAccess` safety net works end-to-end).

**Why these first**: `resolveNav` and `FIELDS` are pure data functions — no mocks, no DOM, instant. They establish the pattern with the least friction and directly test the two areas where bugs have already been found.

### R5 · `dev test` command

**Decision**: Add `test` and `test:portal` subcommands to `tools/dev.py` using `subprocess.run` with the same `_hub_env()` env dict the hub server uses. Stream stdout. Print the interpreter path before running so it is always transparent.

**Why**: Reusing `_hub_env()` ensures the test command picks up the same `VERITY_DATABASE_URL` and other env vars, which matters for integration tests against a local PG instance (though testcontainers doesn't need it, it's correct practice).

### R6 · Coverage floor

**Decision**: `pytest-cov` added to hub dev deps. Floor: `fail_under = 70` in `[tool.coverage.report]`. Not measured during `dev test` by default (slow); measured in `dev test --cov`. CI (when added) always runs with coverage.

**Why 70%**: The hub currently has 67 integration tests and ~10 modules. 70% is achievable without writing unit tests for every internal helper, but high enough to catch obvious gaps. It is a ratchet — rises as tests are added.

### R7 · Help corpus architecture

**Decision**: File-based corpus (`hub/portal/src/help/`) with TypeScript field snippets, static HTML page content (loaded via Vite `?raw` imports), a typed manifest as the metamodel, and `useHelp(path)` / `useHelpPage(path)` hooks for resolution.

**Why not MDX**: MDX requires a Vite plugin and a React renderer. For in-app help pages rendered in a drawer via `innerHTML`, raw HTML is simpler and sufficient — no new build dependencies.

**Why not a DB metamodel**: Content is version-controlled alongside the code that uses it. The manifest is the index. A database would add a migration + API surface for read-only content.

**Why `assessmentCatalog.ts` is the prototype**: `FieldDef` (`label`, `help`, `why`, `options[].note`) is already a well-shaped snippet primitive. The corpus formalizes this shape as `HelpSnippet` and applies it across all forms. `FieldDef` is aliased to `HelpSnippet` for zero-breakage backward compatibility.

**US3 amendment**: Original `HelpPopover` was planned with an inline `content: string` prop. With the corpus, it accepts `helpId: string` — content is resolved from the manifest. The task was renumbered T046 (from the original plan's T024) and depends on corpus foundation tasks T036–T043.

---

## Project Structure

### Documentation (this feature)

```text
specs/004-shell-polish/
├── plan.md              ← this file
├── research.md          ← (inlined above — no separate file needed for this feature)
├── quickstart.md        ← manual walkthrough: fire a toast, trigger 404, run tests
├── contracts/           ← (empty — no new API surface)
└── tasks.md             ← Phase 2 output (/speckit-tasks)
```

### Source Code

```text
hub/portal/src/
├── help/                               NEW — help documentation corpus (Slab C)
│   ├── types.ts                        NEW — HelpSnippet, WorkflowStep, HelpPageLoader, …
│   ├── _manifest.ts                    NEW — typed manifest; the corpus metamodel
│   ├── useHelp.ts                      NEW — useHelp(path) + useHelpPage(path)
│   ├── forms/
│   │   ├── assessment/
│   │   │   ├── fields.ts               NEW — re-export of assessmentCatalog.ts FIELDS
│   │   │   └── _page.html              NEW — full assessment form help page
│   │   ├── intake-create/              NEW — fields.ts + _page.html
│   │   ├── application-onboard/        NEW — fields.ts + _page.html
│   │   ├── evidence-record/            NEW — fields.ts + _page.html
│   │   ├── exception-raise/            NEW — fields.ts + _page.html
│   │   ├── change-proposal/            NEW — fields.ts + _page.html
│   │   └── registry-asset/             NEW — fields.ts + _page.html
│   ├── workflows/
│   │   ├── intake-approval/            NEW — steps.ts + _page.html
│   │   ├── registry-promotion/         NEW — steps.ts + _page.html
│   │   └── obligation-resolution/      NEW — steps.ts + _page.html
│   ├── roles/                          NEW — _overview.html + per-role .html files
│   ├── how-to/                         NEW — _index.ts + per-how-to .html files
│   ├── overview/                       NEW — product.html + glossary.html
│   └── __tests__/
│       └── manifest.test.ts            NEW — corpus validation (labels, loaders, paths)
├── shell/
│   ├── ToastContext.tsx          NEW — toast state (context + useReducer + provider)
│   ├── useToast.ts               NEW — hook: { toast(msg, tone, autoDismiss?, helpId?) }
│   ├── Toast.tsx                 NEW — renders toast stack; "Learn more" when helpId present
│   ├── HelpPopover.tsx           NEW — native popover API; accepts helpId: string (not content: string)
│   ├── HelpDrawer.tsx            NEW — full-page help drawer; driven by helpDrawer singleton
│   ├── AppErrorBoundary.tsx      NEW — class component, catches render errors
│   └── __tests__/
│       └── nav.test.ts           NEW — resolveNav unit tests (Vitest)
├── pages/intakes/
│   └── __tests__/
│       └── assessmentCatalog.test.ts  NEW — FIELDS completeness test
├── api/
│   └── client.ts                 MODIFY — wire toast into error interceptor
└── App.tsx                       MODIFY — mount Toast + AppErrorBoundary + HelpDrawer; add errorElement + /help route

hub/portal/
├── package.json                  MODIFY — add @testing-library/react, jest-dom; add engines
├── .nvmrc                        NEW — "24"
└── tsconfig.app.json             (noUncheckedIndexedAccess already added in 003)

hub/
├── pyproject.toml                MODIFY — add pytest-cov to dev deps; add coverage config
└── .python-version               NEW — "3.14"

tools/
└── dev.py                        MODIFY — add test / test:portal subcommands

.vscode/
└── settings.json                 NEW (created in session) — commit here
```

---

## Quickstart (Phase 1)

```bash
# 1. Run the dev stack
cd tools && python dev.py up

# 2. Open the portal and trigger a toast
# Navigate to an intake → click "Submit for approval"
# → spinner appears if API takes >300ms
# → green "Submitted for approval" toast appears and fades after 4s

# 3. Trigger a 404 screen
# Navigate to http://localhost:5173/intakes/00000000-0000-0000-0000-000000000000
# → "This page doesn't exist" screen with back-to-home link

# 4. Trigger the error boundary (no debug helper — use browser DevTools)
# Open DevTools Console, pause on a component render, then run:
#   throw new Error('boundary test')
# Or temporarily add `throw new Error()` to any component render path.
# → "Something went wrong" screen with error ID and reload button

# 5. Run Python tests via dev
cd /path/to/repo
python tools/dev.py test
# → prints "Using: hub/.venv/bin/python (3.14.4)"
# → runs all 67 pytest tests + coverage report

# 6. Run portal tests
python tools/dev.py test:portal
# → prints "Using: node 24.x"
# → runs Vitest, shows nav.test.ts and assessmentCatalog.test.ts passing

# 7. Confirm VSCode Testing tab
# Open VS Code → Testing tab → should show both pytest tree (67 tests) and
# Vitest tree (3+ tests); run all → all pass
```

---

## Complexity Tracking

No constitution violations. No complexity justification needed.
