# Feature Specification: UI Shell, Auth & Application Onboarding

**Feature Branch**: `002-ui-shell-auth-onboarding`

**Created**: 2026-06-05

**Status**: Draft

**Related specs**:
- Auth backend: `specs/features/user-authentication.md`
- Design system: `specs/ui/design-system.md`
- Wireframe catalog: `specs/ui/wireframe-catalog.md`
- Governance service: `specs/001-verity-governance-service/spec.md`

---

## Context

This spec covers the React + TypeScript implementation of three sequential screen areas that together constitute the first usable product surface for Verity v2. The wireframe kit (`specs/ui/kit/`) is the approved visual source of truth for every screen in scope. The five-layer CSS architecture and token vocabulary in `specs/ui/design-system.md` are normative. The backend auth contract is fully specified in `specs/features/user-authentication.md` and is not re-specified here. The governance service (application-onboarding slice) is already built and its API is the integration target for Milestone 3.

Deliverables are sequenced as three milestones, each independently releasable:

| Milestone | Screens | Dependency |
|---|---|---|
| M1 — Auth shell | Sign-in, auth-state takeovers, account menu, callback handler | Blocks all subsequent milestones |
| M2 — App shell + landing | App chrome (rail/sidebar/topbar/canvas), app launcher, landing page | Requires M1; blocks M3 navigation |
| M3 — Application onboarding | Applications registry, onboard form, approval view, app detail, flow indicators | Requires M2 |

---

## User Scenarios & Testing *(mandatory)*

### User Story 1 — Sign in and land in Verity (Priority: P1)

A governance user navigates to the Verity URL. If unauthenticated they are redirected to the sign-in page. They click "Sign in with Microsoft" and are taken through the Entra OIDC flow. On return they are provisioned (if first visit) and land on the home page already knowing who they are — their display name is visible and their roles are loaded. On a local dev machine a mock-auth path is available below a clearly-labelled warning divider; clicking it provisions the configured synthetic principal through the same provisioning and action-gate path.

**Why this priority**: Authentication is the literal entry point — no other screen is reachable without it. A missing or broken login blocks all downstream development and testing.

**Independent Test**: Navigate to `http://localhost:5173`. Without a session, assert redirect to `/signin`. On local dev, click "Continue as Local Dev". Assert: landing page shown, display name visible in topbar, mock indicator visible in the account-menu dropdown. The Entra path can be exercised against a dev-tenant registration independently of the mock path.

**Acceptance Scenarios**:

1. **Given** an unauthenticated user at any protected route, **when** the page loads, **then** they are redirected to `/signin` with an allow-listed `next` parameter preserving their intended destination.
2. **Given** the sign-in page, **when** a user clicks "Sign in with Microsoft", **then** the browser navigates to `GET /auth/login` (the backend initiates the Entra OIDC redirect).
3. **Given** the OIDC callback route receives `code` and `state`, **when** the component mounts, **then** it calls `GET /auth/callback?code=…&state=…`, on success stores the session and redirects to the allow-listed `next` URL (or `/` if `next` is absent or not on the allow-list).
4. **Given** `VERITY_ENV=local` and `VERITY_AUTH_MODE=mock`, **when** the sign-in page is shown, **then** the mock-auth section is visible with an amber warning card; clicking "Continue as Local Dev" calls `POST /auth/mock` and establishes a session.
5. **Given** `VERITY_ENV` is not `local`, **when** the sign-in page is shown, **then** the mock-auth section is absent with no DOM footprint.
6. **Given** a session that has expired, **when** a protected route is accessed, **then** the "Session expired" full-screen takeover is shown with a "Sign in with Microsoft" action.
7. **Given** an authenticated user without the required role for a route, **when** they navigate to it, **then** the "You don't have permission" full-screen takeover (403) is shown with the specific role named and a "Request access" action.
8. **Given** a principal whose account is disabled (`disabled_at` set), **when** authentication is attempted, **then** the "Account disabled" takeover is shown with a "Contact administrator" action.

---

### User Story 2 — Navigate the product inside the app shell (Priority: P2)

After sign-in a governance user sees the full application chrome: a narrow rail on the left with an app-launcher icon, a contextual sidebar with the active app's navigation, a topbar carrying the Verity wordmark, breadcrumb trail, and account-menu trigger, and a canvas where content lives. Clicking the rail icon opens an app-launcher modal. Clicking their avatar chip opens the account menu showing their identity, platform and app-team roles, and a sign-out option.

**Why this priority**: The shell is the persistent chrome that frames every subsequent product screen. Without it, M3 screens have nowhere to render.

**Independent Test**: After mock-auth login, assert the five shell layout regions are present. Click the rail launcher icon; assert the launcher modal opens. Click the avatar chip; assert the account menu shows display name, email, platform role pills, and sign-out. Click sign-out; assert `POST /auth/logout` is called and the user lands on `/signin`.

**Acceptance Scenarios**:

1. **Given** an authenticated user, **when** the home route loads, **then** the five app shell regions render (`app__rail`, `app__sidebar`, `app__topbar`, `app__canvas`, `app__statusbar`) matching the `sample.html` wireframe layout.
2. **Given** the app shell, **when** the rail launcher icon is clicked, **then** the app-launcher modal opens with a searchable grid of registered apps and a pinned-apps section.
3. **Given** the launcher modal's search field, **when** a user types, **then** the grid filters to matching apps in real time; Escape or an overlay click closes the modal.
4. **Given** the topbar account-menu trigger, **when** clicked, **then** a dropdown shows: display name, email, platform role pills (brand colour), app-team role pills (neutral colour), and a sign-out item.
5. **Given** a mock-auth session, **when** the account menu is open, **then** an amber "Mock auth · local dev" banner is shown at the top of the dropdown.
6. **Given** the sign-out item, **when** clicked, **then** `POST /auth/logout` is called, local session state is cleared, and the user is redirected to `/signin`.
7. **Given** the landing page (`/`), **when** it renders, **then** it shows a welcome heading with the user's `display_name`, quick-stats tiles (from `GET /dashboard/stats`, or placeholder zeros on error), a recent-decisions table (empty-state with getting-started CTA if empty), and jump-back-in cards (empty state if none).

---

### User Story 3 — Browse and onboard an application (Priority: P3)

A governance user navigates to the Applications section, sees a searchable registry, and (if they have the `create_intake` permission) onboards a new application via a multi-step governed form. An approver finds the pending application, reads the composed proposal, and records a decision. The application then appears as `active` in the registry with its detail page accessible.

**Why this priority**: Application onboarding is the first product-value screen and the root of all downstream governance work (use cases, models, approvals).

**Independent Test**: Mock-auth with `ai_governance` role → navigate to `/applications` → click "Onboard application" → complete all steps → assert `POST /applications` fires and success state shown. Switch to approver mock role → find pending application → scroll to end of proposal → click "Approve" → assert `POST /applications/{id}/approve` fires and status updates to `active`.

**Acceptance Scenarios**:

1. **Given** an authenticated user, **when** they navigate to `/applications`, **then** the registry renders with a search/filter bar, a table showing `application_name`, `status` badge, `owner`, and `submitted_at`, and an "Onboard application" CTA visible only to roles with `create_intake` permission.
2. **Given** the registry search field, **when** a user types, **then** results filter to matching application names in real time.
3. **Given** a user without stakeholder access to a specific application, **when** they click its row, **then** a read-only modal opens showing identity, ownership, compliance perimeter, and status — no edit affordances.
4. **Given** a user with `create_intake` permission, **when** they click "Onboard application", **then** the multi-step onboard form opens with visible flow indicators (per `flows.html` and `onboard-application.html`).
5. **Given** the onboard form, **when** the user completes all required fields and submits, **then** `POST /applications` is called; on success the form closes, the registry refreshes, and a success notification is shown.
6. **Given** incomplete required fields on a form step, **when** the user tries to advance, **then** inline validation errors are shown and the step does not advance.
7. **Given** unsaved form data, **when** the user attempts to navigate away, **then** a "Discard changes?" confirmation is shown; confirming discards without sending any request.
8. **Given** a pending application awaiting approval, **when** an approver opens its approval view, **then** the read-only composed proposal is shown and both action buttons ("Approve" / "Return for revision") are disabled until the approver has scrolled to the end.
9. **Given** the approval view with buttons enabled, **when** the approver clicks "Approve", **then** `POST /applications/{id}/approve` is called; on success the application transitions to `active` and the approver is returned to the registry.
10. **Given** the approval view, **when** the approver clicks "Return for revision", **then** `POST /applications/{id}/withdraw` is called; on success the application transitions to `draft`.
11. **Given** an `active` application, **when** the user navigates to `/applications/{id}`, **then** the detail page renders four tabs (Overview, Compliance Perimeter, Use Cases, Team) faithful to `application-detail.html`; the Use Cases tab shows an empty-state CTA if no use cases exist.

---

### Edge Cases

- What happens when `GET /applications` returns an empty list? → Registry shows the empty-state pattern (every screen must ship one per design system §8).
- What happens when the Entra callback includes an `error` parameter? → The callback route redirects to `/signin` without reflecting any IdP error string to the user.
- What happens when the API returns 401 mid-session? → The API client interceptor triggers the "Session expired" full-screen takeover.
- What happens when the API returns 403 for a specific write action (not route-level)? → The inline affordance is disabled or absent; the route-level 403 takeover is not triggered.
- What happens when a `viewer`-only user opens the registry? → "Onboard application" CTA is absent; all rows open read-only modals.
- What happens when the app-launcher has no pinned apps? → The pinned section shows an "Add to favourites" empty state.
- What happens when `GET /dashboard/stats` fails or times out? → Landing page shows placeholder zero values; no error takeover.
- What happens when an onboard form has invalid fields and the user tries to submit? → All invalid fields across all steps are surfaced before any request is sent.

---

## Requirements *(mandatory)*

### Functional Requirements

**Milestone 1 — Auth shell**

- **FR-001**: The sign-in page MUST render as a centred card with the theme-aware Verity wordmark, a "Sign in with Microsoft" primary button, and — when `VERITY_ENV=local` — a mock-auth section below a "LOCAL DEVELOPMENT ONLY" divider, faithful to `specs/ui/kit/pages/signin.html`.
- **FR-002**: The "Sign in with Microsoft" button MUST navigate to `GET /auth/login`; OIDC redirect generation is the backend's responsibility.
- **FR-003**: The callback route (`/auth/callback`) MUST call `GET /auth/callback?code=…&state=…` on mount, show a loading state, and redirect on success or return to `/signin` on error — no IdP error strings reflected in the UI.
- **FR-004**: The mock-auth "Continue as Local Dev" button MUST call `POST /auth/mock`; on success redirect to the allow-listed `next` destination.
- **FR-005**: The mock-auth section MUST have no DOM presence when `VERITY_ENV` is not `local`; enforced by a compile-time environment variable.
- **FR-006**: The three auth-state takeovers (session expired, 403 forbidden, account disabled) MUST render as full-screen pages matching `specs/ui/kit/pages/auth-states.html`, each with its correct icon, status code, body copy, and action button(s).
- **FR-007**: The account-menu dropdown MUST show display name, email, platform role pills (brand colour), app-team role pills (neutral), an amber "Mock auth" banner when the session was established via mock, and a sign-out item.
- **FR-008**: Sign-out MUST call `POST /auth/logout`, clear local session state, and redirect to `/signin`.

**Milestone 2 — App shell + landing**

- **FR-009**: The app shell MUST render the five layout regions (`app__rail`, `app__sidebar`, `app__topbar`, `app__canvas`, `app__statusbar`) with dimensions and collapse behaviour matching `specs/ui/kit/pages/sample.html`.
- **FR-010**: The topbar MUST contain: Verity wordmark (left), breadcrumb trail (centre-left), account-menu avatar chip (right).
- **FR-011**: The app-launcher modal MUST open on rail launcher click, support keyboard search, and close on Escape or overlay click.
- **FR-012**: The landing page MUST show the user's `display_name` in the welcome heading, quick-stats tiles (from `GET /dashboard/stats` or zeros on failure), a recent-decisions table, and jump-back-in cards — all with empty states.
- **FR-013**: Theme (Gray / Slate / Warm) and dark mode MUST be controlled solely by `data-theme` and `.dark` on the root element; no component CSS changes required.

**Milestone 3 — Application onboarding**

- **FR-014**: The applications registry MUST source from `GET /applications`, support real-time client-side search, and show the "Onboard application" CTA only to users with `create_intake` permission.
- **FR-015**: Clicking an application row MUST open a read-only modal for non-stakeholder users; no edit affordances in the modal.
- **FR-016**: The onboard form MUST be a multi-step flow with flow indicators per `specs/ui/kit/pages/flows.html`; step advance requires valid required fields; final submit calls `POST /applications`.
- **FR-017**: Navigating away from an in-progress form MUST show a "Discard changes?" confirmation before discarding without sending any request.
- **FR-018**: The approval view MUST be read-only; action buttons MUST be disabled until the approver scrolls to the end of the composed proposal.
- **FR-019**: "Approve" MUST call `POST /applications/{id}/approve`; "Return for revision" MUST call `POST /applications/{id}/withdraw`.
- **FR-020**: The application detail page MUST render four tabs (Overview, Compliance Perimeter, Use Cases, Team) sourced from `GET /applications/{id}`, with an empty-state CTA on the Use Cases tab when none exist.
- **FR-021**: Every screen in scope MUST have a defined empty state; no screen may be blank or show only an error when data is absent.
- **FR-022**: All API calls MUST go through a single typed API client; it MUST intercept 401 to trigger the session-expired takeover and route-level 403 to trigger the forbidden takeover.

### Key Entities *(include if feature involves data)*

- **Session**: authenticated principal context — `display_name`, `email`, platform roles, app-team roles, `is_mock`; held in React context, never persisted to local/session storage.
- **Application**: governed tenant — `application_id`, `application_name`, `status` (`draft` | `pending_approval` | `active` | `rejected`), `owner_user_id`, `compliance_perimeter`, `submitted_at`.
- **Auth state**: one of `unauthenticated` | `authenticated` | `session_expired` | `forbidden` | `disabled`; drives which full-screen surface renders.

---

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: A user can go from a fresh browser tab (no session) to the post-login landing page in under 10 seconds on a local network, using the mock-auth path.
- **SC-002**: A user with `ai_governance` role can complete a full application onboarding proposal — from clicking "Onboard application" to receiving a success confirmation — in under 5 minutes.
- **SC-003**: An approver can find a pending application, read the full composed proposal, and record an approval decision in under 3 minutes.
- **SC-004**: All three auth-state takeovers are reachable and render correctly in local dev without manual DB edits (mock-mode configuration sufficient).
- **SC-005**: Every screen in scope has a rendered empty state; zero blank or unhandled-error screens on the empty-data path.
- **SC-006**: Theme switching (Gray ↔ Slate ↔ Warm, light ↔ dark) takes effect without a page reload and without component-level style overrides.
- **SC-007**: WCAG AA contrast passes for all screens across all three themes in both light and dark modes.
- **SC-008**: Sign-in and auth-state screens render correctly at 375 px viewport width; the app shell sidebar collapses at the breakpoint defined in the design system.

---

## Assumptions

- The governance service backend (M3 API endpoints) is running locally and its API contract is stable; this spec does not redefine request/response shapes.
- `GET /dashboard/stats` will be added to the governance service alongside this UI work; if absent, the landing page falls back to zero-value tiles without error.
- The React app is served from the existing `hub/` frontend scaffold (Vite + React + TypeScript).
- The five CSS layer files in `specs/ui/kit/styles/` are copied into the React project as-is; no CSS is re-authored from scratch.
- The icon sprite (`specs/ui/kit/icons/sprite.svg`) is served as a static asset; React components use the same `<use href="#i-…">` reference pattern as the wireframe kit.
- `VERITY_ENV` and `VERITY_AUTH_MODE` are injected as Vite build-time environment variables (`import.meta.env.VITE_VERITY_ENV`, `import.meta.env.VITE_AUTH_MODE`).
- Theme selection is a developer/design-time concern for this feature; a user-facing theme picker is out of scope and tracked separately.
- App-team roles in the account menu are scoped to the applications the user is a stakeholder of; the API returns them in the session payload.
- Notification delivery (e.g., notifying a submitter on application return) is out of scope; `shell.toast` is a separate feature.
- Screens in scope: `auth.signin`, `auth.states`, `auth.account-menu`, `auth.callback`, `shell.app`, `shell.launcher`, `home.landing`, `intake.applications`, `intake.onboard`, `intake.onboard-approval`, `intake.app-detail`, `intake.flows`. Studio, Registry, Observability, Governance, Compliance, Settings, and Harness screens are explicitly out of scope.
