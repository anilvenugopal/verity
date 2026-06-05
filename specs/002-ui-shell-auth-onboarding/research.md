# Research: UI Shell, Auth & Application Onboarding

**Date**: 2026-06-05  
**Phase**: 0 — Resolve unknowns before design

---

## 1. Frontend scaffold — does one exist?

**Decision**: No React/Vite scaffold exists in `hub/` today. A new project must be bootstrapped at `hub/portal/`.

**Rationale**: `find hub/ -name "package.json"` returns nothing outside `.venv`. The hub is a Python-only workspace.

**Implementation choice**: Vite 5 + React 18 + TypeScript 5. Vite is the natural choice: fast HMR, first-class TypeScript, trivial proxy config for the FastAPI backend. The portal is a sub-project within the `hub/` workspace — not a separate top-level service (no new constitution complexity violation).

---

## 2. CSS integration strategy

**Decision**: Copy the five kit CSS files from `specs/ui/kit/styles/` into `hub/portal/src/styles/` at project bootstrap. Import them in order in `main.tsx`. No transpilation, no bundler transforms — plain CSS custom properties work natively in all target browsers.

**Rationale**: The kit files are self-contained and tested in the wireframe pages. Copying (not symlinking) keeps the portal independent of the spec directory at build time. Changes to the kit must flow through a deliberate copy + design-system review gate (per the CSS change review gate memory).

**Token extension rule**: Any new token name needed for a React component that does not exist in `tokens.css` must be proposed as a `tokens.css` patch first, reviewed as a design-system change, then copied to the portal. No ad-hoc CSS variables in component files.

---

## 3. Session and auth architecture

**Decision**: Server-side session via signed `HttpOnly` cookie (`SameSite=Lax`). The portal never touches the cookie value — it only calls `GET /me` to learn who is signed in. Session state is held in a React `SessionContext` (in-memory; never `localStorage`/`sessionStorage`).

**Rationale**: This is exactly what the auth spec (FR-013) requires. The portal's job is to reflect the server's answer, not to manage cryptographic state.

**Session bootstrap**: On app mount, `App.tsx` calls `GET /me`. If 401 → set `AuthState = unauthenticated`, redirect to `/signin`. If 200 → set principal in context and render the shell. This is a single request on every hard navigation; in-memory context handles client-side transitions without re-fetching.

**PKCE / OIDC**: The portal does not implement PKCE itself. It navigates to `GET /auth/login` (a hub endpoint); the hub generates and stores `state`, `nonce`, `code_verifier` server-side and 302s to Entra. On callback the portal's `/auth/callback` route simply mounts `AuthCallback.tsx`, which calls `GET /auth/callback?code=…&state=…`. All cryptographic work is server-side.

---

## 4. Auth session endpoints — backend additions

**Decision**: Add `hub/src/verity/hub/auth/session.py` with four routes (`/auth/login`, `/auth/callback`, `/auth/mock`, `/auth/logout`), mounted in `app.py`. Use Starlette's `SessionMiddleware` with the existing `VERITY_SESSION_SECRET`.

**Rationale**: The auth spec is fully detailed. The implementation follows the flow diagram in `specs/features/user-authentication.md` exactly. The four routes are the minimal surface needed for M1 to function.

**Mock-auth endpoint**: `POST /auth/mock` — when `auth_mode=mock && env=local`, creates a server-side session for the configured synthetic principal and returns `{"ok": true}`. The portal calls this from the "Continue as Local Dev" button, then redirects to the `next` URL. If `auth_mode != mock`, the route returns 404 (it is not registered).

**Session middleware key source**: `VERITY_SESSION_SECRET` env var (already in `Settings`). For local dev this can be any 32+ character string. The startup guard already enforces ≥32 chars in prod.

---

## 5. `GET /me` extension

**Decision**: Extend the existing `/me` endpoint response to include `email` and `app_team_roles` (a list of `{application_id, application_name, role}` objects). The `Principal` Pydantic model already carries `email`; `app_team_roles` requires a new DB query joining `actor_app_team_role_grant` → `application`.

**Rationale**: The account menu (FR-007) needs both fields. The extension is backward-compatible (additive).

---

## 6. Permission-gating in the portal

**Decision**: The portal performs no independent authorization calculations. It exposes affordances based solely on the API response:
- `GET /me` → `platform_roles` → client stores and checks against a static role→action map to show/hide CTAs (e.g., "Onboard application" visible only if role includes `ai_governance` or `security`).
- Any 403 from the API on a write attempt → show an inline error message; do not trigger the route-level 403 takeover.
- Route-level 403 (navigating to a protected page without the right role) → backend returns 403 on the `GET /applications` or similar load → portal triggers the forbidden takeover.

**Rationale**: Frontend-only role checks are advisory only and would drift from the backend matrix. The portal trusts the API. The static role→action map is used only for UI affordance (showing/hiding buttons), never for actual authorization.

**Role→action affordance map** (derived from `hub/src/verity/hub/auth/matrix.py`):
- `onboard_application` → `ai_governance`, `security`
- `signoff` → `business_owner`, `compliance`, `legal`, `model_risk`, `ai_governance`, `security`, `privacy`
- `view` → all roles

---

## 7. Approval flow — route mapping

**Decision**: The portal implements the two-step approval flow using the existing routes:

1. **Submitter**: `POST /applications/{id}/submit` → receives `{approval_request_id, ...}` → navigate to the approval view URL `/approvals/{approval_request_id}`.
2. **Approver**: `GET /approvals/{approval_request_id}` → read the composed proposal → `POST /approvals/{approval_request_id}/signoff` with `{decision_code: "approved" | "requested_changes", comment: "..."}` (real `reference.approval_decision` vocabulary; there is no `returned_for_revision`). For `kind=intake` the UI offers approve/`rejected` only.

The spec's simplified route names (`/applications/{id}/approve`) are updated in `data-model.md` and `contracts/portal-api.yaml` to reflect the actual routes. The `tasks.md` sequences submit → signoff correctly.

---

## 8. Routing strategy

**Decision**: React Router v6 with the following route map:

| Path | Component | Protected |
|---|---|---|
| `/signin` | `SignIn` | No |
| `/auth/callback` | `AuthCallback` | No |
| `/` | `AppShell` > `Landing` | Yes |
| `/applications` | `AppShell` > `ApplicationsList` | Yes |
| `/applications/new` | `AppShell` > `OnboardForm` | Yes (onboard_application) |
| `/approvals/:id` | `AppShell` > `ApprovalView` | Yes (view) |
| `/applications/:id` | `AppShell` > `ApplicationDetail` | Yes (view) |
| `*` (catch-all in shell) | `AppShell` > `NotFound` | Yes |

`ProtectedRoute` wraps all authenticated routes. On 401 from `GET /me` it redirects to `/signin?next=<encoded-current-path>` (allow-listed paths only).

---

## 9. Vite proxy configuration

**Decision**: In development, Vite proxies `/api/*` and `/auth/*` to `http://localhost:8000`. The portal uses `/api/applications`, `/api/approvals`, `/auth/login`, etc. In production, FastAPI serves the built `hub/portal/dist/` at `/` and the API routes coexist at their native paths.

**Rationale**: Avoids CORS in development; mirrors the production layout where everything is served from one origin.

---

## 10. Testing approach

**Decision**:
- **Unit**: Vitest + React Testing Library for components (render, user interaction, API mock via `msw`).
- **Integration**: The existing pytest suite tests API endpoints. No E2E browser tests in scope for this feature (deferred).
- **Visual**: The wireframe kit pages (`specs/ui/kit/pages/*.html`) serve as the visual acceptance standard; manual comparison during implementation.

---

# Milestone 4 — Intake lifecycle (research)

## 11. Backend additions for M4

**Decision**: **None.** Every route M4 needs already exists (intake/assessment/intake_approval/approval routers). M4 is frontend-only — it reuses the M1 session + client, the M2 shell, and the M3 `ApprovalView`. Verified against the routers (see plan.md "API Gap Analysis — Milestone 4").

**Rationale**: The 001 backend shipped intake CRUD (slice 1), assessment capture (slice 3), and approval (slice 4). M4 surfaces exactly that — nothing more (the unbuilt tabs/flows are feature 003).

## 12. Assessment save model — the per-tab/full-snapshot constraint

**Decision**: Each shipped tab (AI Decision Impact, Data) has its own **Save** control; saving issues `PUT /intakes/{id}/assessment` with the **full** assessment snapshot (both tabs), producing one SCD-2 revision and a fresh tier computation. The editor holds both tabs' draft state client-side.

**Constraint discovered in planning**: `AssessmentInput` requires **both** `ai_decision_impact` and `data` (neither optional) — there is **no partial PUT**. So a save only persists once both tabs' required fields are valid; a half-finished assessment cannot be persisted tab-by-tab. This honors the clarify decision ("per-tab save") in the only way the shipped backend allows: per-tab Save buttons, full-snapshot PUT, revision-per-save.

**Alternatives considered**: (a) single "Save assessment" button — rejected per the clarify answer; (b) a partial/draft-capture backend that persists one tab at a time — rejected as it would require new backend (out of M4's shipped-only scope; candidate for feature 003 if granular autosave is later wanted).

## 13. Intake sign-off — reject-only, reusing ApprovalView

**Decision**: The intake sign-off view reuses the M3 `ApprovalView` (scroll-gate, `GET /approvals/{id}`, `POST …/signoff`) with `kind=intake`, rendering **approve/reject only**. The "Return for revision" button is omitted for `kind=intake`.

**Rationale**: The shipped intake-approval backend has no withdraw/return route (`withdraw_approval` is an orphan action with no endpoint). Offering "Return for revision" would call a non-existent route. `ApprovalView` takes a `kind`/`returnable` prop so the same component serves both onboarding (returnable) and intake (reject-only). Separation of duty is enforced backend-side (submitter→403); the UI presents the sign-off as a disabled affordance for the submitter, not a takeover.

## 14. Editing during an open approval — allow-but-warn

**Decision**: While the intake is `in_review` (approval open), assessment/requirement edits stay enabled (the backend blocks only terminal status), and the detail + assessment surfaces show a banner that re-saving may change the computed tier and the required quorum.

**Rationale**: Faithful to the shipped backend (no in_review lock) while surfacing the governance hazard. A UI-side hard lock was considered but rejected during clarify (it would diverge from backend behavior and hide a real state the backend permits).

## 15. Routing additions for M4

**Decision**: Add to the React Router map:

| Path | Component | Protected |
|---|---|---|
| `/applications/:appId/intakes/new` | `intakes/IntakeCreate` | Yes (`create_intake` affordance) |
| `/intakes/:id` | `intakes/IntakeDetail` (hosts `AssessmentTabs`) | Yes (`view`) |
| `/approvals/:id` | `applications/ApprovalView` (already exists; now kind-aware) | Yes (`view`) |

The intake create entry is reached from the application detail Use Cases tab; the approval route is shared with onboarding and dispatches on the approval's `request_kind_code`.
