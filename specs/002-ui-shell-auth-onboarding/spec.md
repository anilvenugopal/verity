# Feature Specification: UI Shell, Auth, Application Onboarding & Intake Lifecycle

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

This spec covers the React + TypeScript implementation of four sequential screen areas that together constitute the first usable product surface for Verity v2 — a portal over **everything the governance backend already supports**. The wireframe kit (`specs/ui/kit/`) is the approved visual source of truth for every screen in scope. The five-layer CSS architecture and token vocabulary in `specs/ui/design-system.md` are normative. The backend auth contract is fully specified in `specs/features/user-authentication.md` and is not re-specified here. The governance service is already built — its application-onboarding slice is the integration target for Milestone 3, and its **shipped intake slices (CRUD, assessment capture, approval)** are the integration target for Milestone 4.

Deliverables are sequenced as four milestones, each independently releasable:

| Milestone | Screens | Dependency |
|---|---|---|
| M1 — Auth shell | Sign-in, auth-state takeovers, account menu, callback handler | Blocks all subsequent milestones |
| M2 — App shell + landing | App chrome (rail/sidebar/topbar/canvas), app launcher, landing page | Requires M1; blocks M3 navigation |
| M3 — Application onboarding | Applications registry, onboard form, approval view, app detail, flow indicators | Requires M2 |
| M4 — Intake lifecycle | Intake create, intake detail, assessment (shipped tabs), submit + tier-quorum sign-off | Requires M2 (shell) + M3 (approval view + an `active` application to attach intakes to) |

**M4 scope guardrail**: M4 surfaces *only* intake backend that has already shipped in `001` — intake CRUD (slice 1), the two shipped assessment tabs (AI Decision Impact + Data) with the computed tier/materiality readout (slice 3), and submit → tier-quorum approval (slice 4). It explicitly does **not** include the Security & Access tab, mitigations, the Risk & Obligations summary tab (FR-AS-004–010), obligation-resolution display (FR-IN-014), or change-proposal flows (FR-IN-013) — that backend is not built; those screens land in feature `003` alongside their backend. M4 reuses the M3 approval/sign-off view (scroll-gate) with `kind=intake`.

---

## Clarifications

### Session 2026-06-05

- Q: For M4's intake sign-off view — the shipped intake-approval backend has no withdraw/return route. Reject-only, or also "Return for revision"? → A: **Reject-only** (approve/reject). The M3 "Return for revision" button is omitted for `kind=intake`; a rejected sign-off resolves the request as rejected. (Stays inside M4's shipped-only scope.)
- Q: How should the UI save the two shipped assessment tabs? → A: **Per-tab save** — saving a tab fires a PUT carrying the **full assessment snapshot** (the backend captures the whole assessment as one SCD-2 revision; there is no partial-PUT), so each tab save writes a revision and recomputes the tier.
- Q: The backend allows editing an assessment while an approval is open (`in_review`), which would recompute the tier under reviewers. What should M4 do? → A: **Allow, but warn** — edits stay enabled (following the backend), but while an approval is open the intake surfaces a banner that re-saving may change the tier/quorum.
- Q: Which permission gates the "New intake" CTA? → A: **`create_intake`** (resolved from the backend route gate — same action as onboarding's CTA; not a user decision, recorded for traceability).

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

### User Story 4 — Create an intake under an application (Priority: P4)

A governance user opens an `active` application, starts a new intake (a proposed AI use case), gives it a title and initial requirements, and lands on the intake detail page where its status, requirements, and assessment progress are visible. This is the entry point of the intake lifecycle and the first M4 screen.

**Why this priority**: Nothing downstream in M4 (assessment, approval) is reachable without an intake to operate on; it depends on M3 because an intake must attach to an `active` application.

**Independent Test**: Mock-auth with an authoring role (`VERITY_MOCK_PLATFORM_ROLES=engineer`). Navigate to an `active` application → click "New intake" → enter a title → submit → assert `POST /applications/{application_id}/intakes` fires and the intake detail page (`intake.usecase-detail`) renders with status `proposed`. Add a requirement → assert `POST /intakes/{intake_id}/requirements` fires and the requirement appears in the list.

**Acceptance Scenarios**:

1. **Given** an `active` application detail page, **when** a user with an authoring role views it, **then** a "New intake" CTA is visible (absent for `viewer`-only users), and the Use Cases tab lists existing intakes from `GET /applications/{application_id}/intakes` with title + status badge, or an empty-state CTA when none exist.
2. **Given** the "New intake" form (`intake.usecase-create`), **when** the user submits a valid title, **then** `POST /applications/{application_id}/intakes` is called; on success the form closes and the user lands on `/intakes/{intake_id}` showing status `proposed`.
3. **Given** the intake detail page (`intake.usecase-detail`), **when** it loads, **then** it sources from `GET /intakes/{intake_id}` and renders title, status badge, the requirements list (`GET /intakes/{intake_id}/requirements`), and an assessment-progress indicator.
4. **Given** the requirements list on intake detail, **when** the user adds a requirement, **then** `POST /intakes/{intake_id}/requirements` is called and the new requirement appears without a full page reload.
5. **Given** an intake in a terminal status (`rejected`/`retired`), **when** the detail page loads, **then** edit affordances (add requirement, edit assessment, submit) are disabled.

---

### User Story 5 — Capture the shipped assessment tabs and see the computed tier (Priority: P5)

From an intake's detail page the user opens the assessment and fills the two shipped tabs — **AI Decision Impact** and **Data** — then sees the system-computed risk tier and NAIC materiality with the rationale, plus the recorded inherent tier. This is the classification step that gates approval.

**Why this priority**: A computed tier is the precondition for submission (US6); it requires an intake (US4) to exist.

**Independent Test**: Mock-auth with an authoring role. Open an intake → open the assessment → complete the AI Decision Impact and Data tabs → save → assert `PUT /intakes/{intake_id}/assessment` fires and the computed tier + materiality readout renders from `GET /intakes/{intake_id}/assessment`. Re-open the assessment → assert prior answers are reloaded (revision history available via `GET /intakes/{intake_id}/assessment/revisions`).

**Acceptance Scenarios**:

1. **Given** the intake detail page, **when** the user opens the assessment, **then** exactly two tabs are shown — "AI Decision Impact" and "Data" — and no unbuilt tabs (Security & Access, Mitigations, Risk & Obligations) are present.
2. **Given** the assessment tabs, **when** the user saves a tab, **then** `PUT /intakes/{intake_id}/assessment` is called with the full assessment snapshot (one new revision) and the response's computed `ai_risk_tier` + materiality + rationale render in a read-only summary panel.
3. **Given** a saved assessment, **when** the assessment is re-opened, **then** `GET /intakes/{intake_id}/assessment` reloads the captured answers and the latest computed tier; prior revisions are listed from `GET /intakes/{intake_id}/assessment/revisions`.
4. **Given** an assessment whose answers compute an `unacceptable` tier, **when** it is saved, **then** the UI surfaces that the intake is auto-rejected and offers no submit affordance.
5. **Given** an assessment with incomplete required fields, **when** the user attempts to save, **then** inline validation is shown and no request is sent until the tab is valid.

---

### User Story 6 — Submit an assessed intake and sign off the tier quorum (Priority: P6)

An author submits an assessed intake for approval, which opens a `kind=intake` approval requiring the tier-based quorum (FR-IN-005). Approvers — who must be different people than the submitter (separation of duty) — open the approval view, read the composed intake, and sign off; once the full quorum approves, the intake moves to `approved`. This reuses the M3 approval/sign-off view with `kind=intake`.

**Why this priority**: This is the terminal step of the lifecycle and depends on a computed tier from US5; it is the lowest-priority M4 story because it builds on everything before it.

**Independent Test**: Mock-auth as the author (`engineer`) → open an assessed intake → click "Submit for approval" → assert `POST /intakes/{intake_id}/submit` fires and returns an `approval_request_id` with `required_roles` for the tier. Switch to a quorum role that differs from the submitter (e.g. `VERITY_MOCK_PLATFORM_ROLES=business_owner`) → open the approval view → scroll to the end → sign off → assert `POST /approvals/{approval_request_id}/signoff` fires; once all required roles approve, the intake shows `approved`.

**Acceptance Scenarios**:

1. **Given** an intake with a computed tier and no open approval, **when** the author clicks "Submit for approval", **then** `POST /intakes/{intake_id}/submit` is called; on success the intake advances to `in_review` and the returned `required_roles` (the tier quorum) are shown.
2. **Given** an intake with no computed tier, **when** the user views it, **then** the "Submit for approval" affordance is disabled with copy explaining the assessment must be completed first.
3. **Given** an open `kind=intake` approval, **when** an approver opens the approval view, **then** it reuses the M3 scroll-gated view (`intake.usecase-review`) sourced from `GET /approvals/{approval_request_id}`, showing the composed intake and the quorum progress (which roles have signed), with **approve/reject** actions only — no "Return for revision" button.
4. **Given** the approval view, **when** the signed-in approver is the same actor who submitted, **then** the sign-off action is disabled/forbidden (separation of duty — the backend returns 403 and the UI reflects it as a disabled affordance, not a takeover).
5. **Given** the approval view with the scroll-gate satisfied, **when** an approver holding a required role signs "approve", **then** `POST /approvals/{approval_request_id}/signoff` is called with `decision_code: "approved"`; the quorum progress updates.
6. **Given** the final required sign-off, **when** it is recorded, **then** the intake transitions to `approved` and the approver is returned to the intake detail page showing the `approved` status.
7. **Given** any approver signs "rejected", **when** the sign-off is recorded, **then** the approval request resolves as rejected and the intake reflects the rejected outcome.

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
- What happens when a user opens an intake whose assessment is not yet started? → The assessment-progress indicator shows "not started" and the "Submit for approval" affordance is disabled.
- What happens when a user tries to submit an intake that already has an open approval? → The backend returns 409; the UI shows the existing approval rather than opening a second one.
- What happens when the submitter opens the approval view for their own intake? → The sign-off action is disabled (separation of duty); no full-screen takeover.
- What happens when an assessment computes an `unacceptable` tier? → The intake is auto-rejected; the UI shows the rejected outcome and offers no submit path.
- What happens when the author edits the assessment while an approval is open (`in_review`)? → Edits stay enabled (the backend blocks only terminal status), but a banner warns that re-saving may change the computed tier and the required quorum (FR-032).
- What happens when an intake list for an application is empty? → The Use Cases tab shows the empty-state CTA ("Create the first intake").

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

**Milestone 4 — Intake lifecycle**

- **FR-023**: The application detail Use Cases tab MUST list the application's intakes from `GET /applications/{application_id}/intakes` (title + status badge) with an empty-state CTA, and show a "New intake" CTA only to users with the `create_intake` permission (the action the backend route gates on).
- **FR-024**: The intake create form (`intake.usecase-create`) MUST submit via `POST /applications/{application_id}/intakes`; on success it MUST route to `/intakes/{intake_id}` (the detail page).
- **FR-025**: The intake detail page (`intake.usecase-detail`) MUST source from `GET /intakes/{intake_id}` and render title, status badge, the requirements list (`GET /intakes/{intake_id}/requirements`), and an assessment-progress indicator; adding a requirement MUST call `POST /intakes/{intake_id}/requirements` and update the list in place.
- **FR-026**: The assessment surface MUST render exactly the two shipped tabs — "AI Decision Impact" and "Data" — and MUST NOT render the Security & Access, Mitigations, or Risk & Obligations tabs (their backend is not built; they belong to feature `003`).
- **FR-027**: The assessment saves **per tab** — saving a tab MUST call `PUT /intakes/{intake_id}/assessment` carrying the **full assessment snapshot** (both shipped tabs' current values; the backend captures the whole assessment as one SCD-2 revision — there is no partial PUT). Each tab save therefore writes a new revision and recomputes the tier. The response's computed risk tier, NAIC materiality, and rationale MUST render in a read-only summary panel after each save. Re-opening MUST reload captured answers via `GET /intakes/{intake_id}/assessment`, with prior revisions available from `GET /intakes/{intake_id}/assessment/revisions`.
- **FR-028**: The "Submit for approval" affordance MUST be disabled until a risk tier has been computed; it MUST call `POST /intakes/{intake_id}/submit` and surface the returned tier-quorum `required_roles`. An `unacceptable` tier MUST show the auto-rejected outcome and offer no submit path.
- **FR-029**: The intake approval/sign-off view (`intake.usecase-review`) MUST reuse the Milestone 3 scroll-gated approval view with `kind=intake`, sourced from `GET /approvals/{approval_request_id}`, showing the composed intake and quorum progress; sign-off MUST call `POST /approvals/{approval_request_id}/signoff`. The view MUST offer **approve/reject only** — the M3 "Return for revision" button MUST be omitted for `kind=intake` (the shipped backend has no withdraw/return route for intake); a "rejected" sign-off resolves the request as rejected.
- **FR-030**: When the signed-in approver is the actor who submitted the intake, the sign-off action MUST be presented as a disabled affordance (separation of duty); the backend 403 MUST NOT trigger the route-level forbidden takeover.
- **FR-031**: Every M4 screen MUST have a defined empty state and MUST disable all write affordances for an intake in a terminal status (`rejected`/`retired`).
- **FR-032**: While an approval is open (`in_review`), assessment and requirement edits MUST remain enabled (following the backend, which blocks only terminal status), but the intake detail and assessment surfaces MUST show a banner warning that an approval is open and re-saving may change the computed tier and required quorum.

### Key Entities *(include if feature involves data)*

- **Session**: authenticated principal context — `display_name`, `email`, platform roles, app-team roles, `is_mock`; held in React context, never persisted to local/session storage.
- **Application**: governed tenant — `application_id`, `application_name`, `status` (`draft` | `pending_approval` | `active` | `rejected`), `owner_user_id`, `compliance_perimeter`, `submitted_at`.
- **Auth state**: one of `unauthenticated` | `authenticated` | `session_expired` | `forbidden` | `disabled`; drives which full-screen surface renders.
- **Intake**: a proposed AI use case under an application — `intake_id`, `application_id`, `title`, `intake_status` (`proposed` | `in_review` | `approved` | `rejected` | `retired`), `ai_risk_tier` (computed, nullable until assessed), requirements list.
- **Assessment**: the captured classification input for an intake — the two shipped tabs (AI Decision Impact, Data) plus the computed read-back (`ai_risk_tier`, materiality, rationale, inherent tier); revisioned (SCD-2 on the backend).
- **Intake approval**: a `kind=intake` instance of the shared approval entity — `approval_request_id`, `required_roles` (the tier quorum), per-role sign-off progress, resolved status; same primitive as application onboarding.

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
- **SC-009**: A user with an authoring role can create an intake under an `active` application and reach its detail page in under 2 minutes using mock auth.
- **SC-010**: A user can complete the two shipped assessment tabs and see a computed risk tier + materiality without a page reload, sourced from real backend computation (no mocked tier).
- **SC-011**: A full intake lifecycle — create → assess → submit → tier-quorum sign-off → `approved` — is demonstrable end-to-end in local dev using only mock-auth role switches (an authoring role to submit, a distinct quorum role to sign off), with no manual DB edits.
- **SC-012**: The assessment surface shows only the two shipped tabs; the unbuilt tabs (Security & Access, Mitigations, Risk & Obligations) have no DOM presence.

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
- Screens in scope: `auth.signin`, `auth.states`, `auth.account-menu`, `auth.callback`, `shell.app`, `shell.launcher`, `home.landing`, `intake.applications`, `intake.onboard`, `intake.onboard-approval`, `intake.app-detail`, `intake.flows` (M1–M3); plus `intake.usecase-create`, `intake.usecase-detail`, `intake.usecase-review`, and the two shipped assessment tabs (M4). Studio, Registry, Observability, Governance, Compliance, Settings, and Harness screens are explicitly out of scope.
- M4 integrates against intake backend that **already exists** in the governance service (`hub` modules `intake/`, `assessment/`, `intake_approval/`, `approval/`); M4 is almost entirely frontend plus the same read-wiring pattern as M1–M3. No new intake backend is built in this feature — the unbuilt assessment tabs and change-proposal flows are deferred to feature `003`.
- M4 reference prototype: `specs/ui/verity-intake-wireframe.html` (strangler); the intake tier-quorum sign-off reuses the M3 approval/sign-off view with `kind=intake`.
- M4 requires an `active` application (from M3) to attach intakes to; the author and the approver must be distinct principals (separation of duty), exercised via mock-auth role switches.
