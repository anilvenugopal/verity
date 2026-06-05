# Implementation Plan: UI Shell, Auth & Application Onboarding

**Branch**: `001-verity-governance-service` (spec tracked here) | **Date**: 2026-06-05 | **Spec**: [spec.md](spec.md)

## Summary

Build the first usable React + TypeScript product surface for Verity v2 — sign-in (Entra OIDC + local-dev mock), the persistent app shell, a landing page, and the application-onboarding workflow — wired to the existing governance API. The CSS/icon kit in `specs/ui/kit/` is the approved visual source; the five-layer CSS files are copied verbatim into the React project. The backend auth session endpoints (`/auth/login`, `/auth/callback`, `/auth/mock`, `/auth/logout`) are missing from the current hub implementation and must be added alongside the frontend work.

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

**Scale/Scope**: ~12 screens (M1: 4, M2: 3, M3: 5), single SPA, single tenant.

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
│           └── applications/
│               ├── ApplicationsList.tsx    (intake.applications)
│               ├── OnboardForm.tsx         (intake.onboard — multi-step)
│               ├── ApprovalView.tsx        (intake.onboard-approval)
│               └── ApplicationDetail.tsx   (intake.app-detail + tabs)
│
└── src/verity/hub/
    └── auth/
        └── session.py             ← NEW: /auth/login, /auth/callback, /auth/mock, /auth/logout
                                      (session middleware + OIDC client wiring per user-authentication.md)
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
- The spec says `POST /applications/{id}/approve` — actual flow is: `POST /applications/{id}/submit` (submitter) → `GET /approvals/{approval_request_id}` (approver reads) → `POST /approvals/{approval_request_id}/signoff` with `decision_code: "approved"` or `"returned_for_revision"`.
- The portal must first call `/submit` to get the `approval_request_id`, then surface the approval view from `GET /approvals/{id}`.
- The `tasks.md` must sequence this correctly.

**Dashboard stats**: `GET /dashboard/stats` does not yet exist. The landing page falls back to zero-value tiles if the endpoint is absent (HTTP 404 → show zeros, no error takeover). The endpoint can be added in a follow-on task.
