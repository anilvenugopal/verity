# Implementation Plan: UI Shell, Auth, Application Onboarding & Intake Lifecycle

**Branch**: `002-ui-shell-auth-onboarding` | **Date**: 2026-06-05 | **Spec**: [spec.md](spec.md)

## Summary

Build the first usable React + TypeScript product surface for Verity v2 — a portal over **everything the governance backend already supports**: sign-in (local-dev mock first; Entra OIDC scaffolded), the persistent app shell, a landing page, the application-onboarding workflow (M3), and the **intake lifecycle** (M4: create → assess → submit → tier-quorum sign-off). The CSS/icon kit in `specs/ui/kit/` is the approved visual source; the five-layer CSS files are copied verbatim into the React project. The backend auth session endpoints (`/auth/login`, `/auth/callback`, `/auth/mock`, `/auth/logout`) are added alongside M1 frontend work. **M4 adds no new backend** — it is pure frontend over the already-shipped intake/assessment/approval routes, with the same `GET /me`-style read wiring as M1–M3.

---

## Technical Context

**Language/Version**: TypeScript 5.x (frontend); Python 3.12 (backend supplement — auth endpoints only)

**Primary Dependencies**:
- Frontend: React 18, Vite 5, React Router v6, plain CSS custom properties (kit CSS — no Tailwind, no CSS-in-JS)
- Backend additions: FastAPI session middleware (starlette `SessionMiddleware` or equivalent), `itsdangerous` for signed cookies, `msal` for Entra PKCE (already in auth spec)

**Storage**: No frontend-local state persistence — session is a server-side HttpOnly cookie; React holds resolved principal in context (memory only).

**Testing**: Vitest + React Testing Library (frontend); existing pytest (backend additions)

**Target Platform**: Browser (modern Chromium/Firefox/Safari); served from `hub/portal/` via Vite dev server in development, static build served by FastAPI in production.

**Project Type**: Web application — React SPA (portal) + FastAPI backend (existing hub, extended with auth endpoints)

**Performance Goals**: Initial sign-in to landing page < 10 s on local network (SC-001); form completion flows < 5 min (SC-002).

**Constraints**:
- CSS is the five-layer kit — no new component styles without updating `tokens.css` first; no Tailwind, no CSS-in-JS.
- No frontend-side authorization logic — all permission decisions come from the API; the portal only hides/shows affordances based on what the API returns.
- Mock-auth section must have zero DOM presence when `VITE_VERITY_ENV` ≠ `local`.

**Scale/Scope**: ~15 screens (M1: 4, M2: 3, M3: 5, M4: 3 — intake create/detail/review), single SPA, single tenant. M4 reuses the M3 **tab-gated sign-off gate** (extracted from `ApplicationWorkspace`) for `kind=intake` and the shipped assessment tabs.

---

## Constitution Check

*GATE: Must pass before Phase 0 research. Re-checked after Phase 1 design.*

| Principle | Status | Notes |
|---|---|---|
| **I — Spec Precedes Implementation** | ✅ PASS | `specs/002-ui-shell-auth-onboarding/spec.md` exists and is reviewed. |
| **II — Schema Is the Hardened Foundation** | ✅ PASS | This feature is purely UI + auth-session layer. No new DB schema is introduced. The existing `actor`, `actor_role`, and application tables (already in `verity_schema.sql` and used by the hub) are read-only from the portal's perspective. |
| **III — Legacy Is Reference, Never Source** | ✅ PASS | CSS kit, wireframes, and design system are v2 artifacts authored from scratch. No import from `../verity_legacy`. |
| **IV — API-Only Governance Boundary** | ✅ PASS | The portal communicates with the hub exclusively via HTTP. The portal holds no DB credentials. Auth session state is managed by the hub; the portal reads it through `GET /me`. |
| **V — Uniform Bindings, Agent-Only Tools** | N/A | This feature introduces no tasks, agents, or binding declarations. |
| **VI — Equity-Research Slice First** | ✅ PASS | UI work is sequenced after intake/onboarding backend slices (already shipped). No v1 capability is silently dropped — the portal implements the auth + onboarding surface that the backend already supports. |
| **VII — Governed Deployment** | N/A | Portal is a static build + FastAPI-served asset; no harness packages or deployment gates involved. |
| **VIII — Continuous Compliance** | N/A | Compliance controls are downstream of onboarding; not triggered by the portal itself at this milestone. |
| **Naming gate** | ✅ PASS | All TypeScript identifiers mirror the backend snake_case field names via the API client types (e.g. `application_id`, `display_name`, `platform_roles`). React component names are PascalCase (standard). No divergence from the backend naming convention. |
| **Boundary gate** | ✅ PASS | Auth session endpoints to be added to the hub backend follow the same fail-closed, action-gated FastAPI pattern as existing routes. |

**No violations. Cleared for Phase 0.**

**M4 post-design re-check (2026-06-05)**: still clean. M4 introduces **no new DB schema** (reads/writes the already-shipped intake/assessment/approval tables via existing routes — Principle II holds), **no backend additions** (API-only boundary IV holds — the portal calls existing HTTP routes), and all TypeScript types mirror backend snake_case field names verbatim (naming gate holds; see data-model.md §8–13). No legacy import (III). No agent/binding/deployment surface (V/VII N/A).

---

## Project Structure

### Documentation (this feature)

```text
specs/002-ui-shell-auth-onboarding/
├── plan.md              ← this file
├── research.md          ← Phase 0 output
├── data-model.md        ← Phase 1 output
├── quickstart.md        ← Phase 1 output
├── contracts/
│   └── portal-api.yaml  ← Phase 1 output (OpenAPI subset consumed by the portal)
├── checklists/
│   └── requirements.md
└── tasks.md             ← Phase 2 output (/speckit-tasks)
```

### Source Code

```text
hub/
├── portal/                        ← NEW: Vite + React + TypeScript SPA
│   ├── index.html
│   ├── vite.config.ts             (proxy /api → localhost:8000 in dev)
│   ├── tsconfig.json
│   ├── package.json
│   ├── public/
│   │   ├── sprite.svg             (copied from specs/ui/kit/icons/sprite.svg)
│   │   └── assets/                (copied from specs/ui/kit/assets/ — wordmarks)
│   └── src/
│       ├── main.tsx
│       ├── App.tsx                (root: routes + SessionProvider + ThemeProvider)
│       ├── styles/                (copied verbatim from specs/ui/kit/styles/)
│       │   ├── tokens.css
│       │   ├── base.css
│       │   ├── layout.css
│       │   ├── components.css
│       │   └── utilities.css
│       ├── api/
│       │   └── client.ts          (typed fetch wrapper; 401→session-expired, 403→forbidden)
│       ├── auth/
│       │   ├── SessionContext.tsx  (React context: Principal | null + AuthState)
│       │   ├── ProtectedRoute.tsx  (redirects unauthenticated to /signin)
│       │   └── useSession.ts       (hook over SessionContext)
│       ├── shell/
│       │   ├── AppShell.tsx        (rail + sidebar + topbar + canvas + statusbar)
│       │   ├── Rail.tsx
│       │   ├── Sidebar.tsx
│       │   ├── Topbar.tsx
│       │   ├── AccountMenu.tsx
│       │   └── AppLauncher.tsx
│       └── pages/
│           ├── SignIn.tsx          (auth.signin wireframe)
│           ├── AuthCallback.tsx    (auth.callback — no UI, only session mint)
│           ├── AuthStatePage.tsx   (auth.states — session-expired/forbidden/disabled)
│           ├── Landing.tsx         (home.landing wireframe)
│           ├── applications/
│           │   ├── ApplicationsList.tsx       (intake.applications)
│           │   ├── OnboardForm.tsx            (workspace create mode — Identity card + tabs + required-field UX)
│           │   └── ApplicationWorkspace.tsx   (view/approve — identity band, tabs, Risk Profile + Governance rail,
│           │       #                            history; the sign-off gate lives here. M3 SHIPPED THIS — it replaced
│           │       #                            the planned ApplicationDetail + ApprovalView + StatusBadge. A Use
│           │       #                            cases tab is added in M4; extract the sign-off gate as shared.)
│           └── intakes/                     ← M4
│               ├── IntakeCreate.tsx        (intake.usecase-create — form under an application)
│               ├── IntakeDetail.tsx        (intake.usecase-detail — status, requirements, assessment progress,
│               │   #                          + Governance & Approval panel reusing the shared sign-off gate)
│               └── AssessmentTabs.tsx      (the two shipped tabs: AI Decision Impact + Data; per-tab save)
│
└── src/verity/hub/
    └── auth/
        └── session.py             ← NEW (M1 only): /auth/login, /auth/callback, /auth/mock, /auth/logout
                                      (session middleware + OIDC client wiring per user-authentication.md)
                                      # M4 adds NO backend files — intake/assessment/approval routes already exist
```

**Structure Decision**: Web application — React SPA in `hub/portal/`, backend extensions in `hub/src/verity/hub/auth/session.py`. The portal is a separate Vite project within the hub workspace; in production it is built to `hub/portal/dist/` and served by FastAPI as a static mount. No new top-level service is introduced.

---

## Complexity Tracking

No constitution violations. No complexity tracking required.

---

## API Gap Analysis

The spec's auth endpoints are not yet in the running hub. These must be added before M1 frontend can complete integration testing:

| Endpoint | Status | Notes |
|---|---|---|
| `GET /auth/login` | **MISSING** | Mints `state`+`nonce`+PKCE, stores in session, 302 → Entra `/authorize` |
| `GET /auth/callback` | **MISSING** | Verifies `state`, exchanges code, validates ID token, JIT-provisions, issues session cookie |
| `POST /auth/mock` | **MISSING** | Local-dev only; establishes session for the configured synthetic principal; guarded `auth_mode=mock && env=local` |
| `POST /auth/logout` | **MISSING** | Invalidates server-side session, redirects to `/signin` |
| `GET /me` | **EXISTS** — needs extension | Currently returns `{actor_id, display_name, platform_roles}`; needs `email` and `app_team_roles` added for the account menu |
| `GET /applications` | **EXISTS** | `require_action("view")` |
| `POST /applications` | **EXISTS** | `require_action("onboard_application")` |
| `GET /applications/{id}` | **EXISTS** | `require_action("view")` |
| `POST /applications/{id}/submit` | **EXISTS** | Submits to approval queue |
| `GET /approvals/{id}` | **EXISTS** | Read approval request |
| `POST /approvals/{id}/signoff` | **EXISTS** | Records approve/return decision |

**Approval flow mapping** (spec vs. actual routes):
- The spec (FR-019, now corrected) uses the shared primitive — actual flow is: `POST /applications/{id}/submit` (submitter) → `GET /approvals/{approval_request_id}` (approver reads) → `POST /approvals/{approval_request_id}/signoff` with `decision_code: "approved"` or `"requested_changes"` (real vocab; no `returned_for_revision`, no `/approve` or `/withdraw` route).
- The portal must first call `/submit` to get the `approval_request_id`, then surface the approval view from `GET /approvals/{id}`.
- The `tasks.md` must sequence this correctly.

**Dashboard stats**: `GET /dashboard/stats` does not yet exist. The landing page falls back to zero-value tiles if the endpoint is absent (HTTP 404 → show zeros, no error takeover). The endpoint can be added in a follow-on task.

---

## API Gap Analysis — Milestone 4 (Intake lifecycle)

**No backend additions.** Every endpoint M4 consumes already exists in the hub (verified against the routers). M4 is frontend-only.

| Endpoint | Status | Action gate | Notes |
|---|---|---|---|
| `POST /applications/{application_id}/intakes` | **EXISTS** | `create_intake` | Create an intake under an application → returns `Intake` (status `proposed`) |
| `GET /applications/{application_id}/intakes` | **EXISTS** | `view` | List an application's intakes (Use Cases tab) |
| `GET /intakes/{intake_id}` | **EXISTS** | `view` | Intake detail |
| `POST /intakes/{intake_id}/requirements` | **EXISTS** | (intake author) | Add a requirement |
| `GET /intakes/{intake_id}/requirements` | **EXISTS** | `view` | List requirements |
| `PUT /intakes/{intake_id}/assessment` | **EXISTS** | `edit_impact_assessment` | Capture the whole assessment (one SCD-2 revision); per-tab save sends the full snapshot |
| `GET /intakes/{intake_id}/assessment` | **EXISTS** | `view` | Reload captured answers + computed tier/materiality |
| `GET /intakes/{intake_id}/assessment/revisions` | **EXISTS** | `view` | Revision history |
| `POST /intakes/{intake_id}/submit` | **EXISTS** | `edit_intake` | Submit for approval (requires computed tier); advances `proposed→in_review`; returns `ApprovalRequest` (`kind=intake`) with `required_roles` |
| `GET /approvals/{approval_request_id}` | **EXISTS** | `view` | Read the intake approval (kind-dispatched) — REUSED from M3 |
| `POST /approvals/{approval_request_id}/signoff` | **EXISTS** | `signoff` | Sign off; separation of duty enforced backend-side (submitter→403); REUSED from M3 |

**Clarification-driven behaviors (Session 2026-06-05):**
- **Reject-only**: the reused **shared sign-off gate** (extracted from `ApplicationWorkspace`) omits the "Request changes" button when `kind=intake` (no withdraw route exists for intake). `decision_code` ∈ {`approved`, `rejected`}.
- **Per-tab save**: each assessment tab save issues `PUT …/assessment` with the **full** assessment snapshot → one revision per save; the response's computed tier re-renders.
- **Allow-but-warn**: edits stay enabled in `in_review` (backend blocks only terminal status); the detail/assessment surfaces show a banner that re-saving may change the tier/quorum.
- **New-intake CTA**: gated on `create_intake` (matches the backend route gate).
