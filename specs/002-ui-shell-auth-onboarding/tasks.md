# Tasks: UI Shell, Auth, Application Onboarding & Intake Lifecycle

**Input**: Design documents from `specs/002-ui-shell-auth-onboarding/`

**Prerequisites**: plan.md ✅ · spec.md ✅ · research.md ✅ · data-model.md ✅ · contracts/portal-api.yaml ✅

**Tests**: No test tasks are generated — not requested in the spec. Vitest/RTL setup is scaffolded in Phase 1 for later use.

**Organization**: Tasks are grouped by user story. US1 (auth) → US2 (shell) → US3 (onboarding) → **US4 (intake create) → US5 (assessment) → US6 (submit + sign-off)**. Each phase is independently deployable and demonstrable.

**Milestones**: T001–T043 = M1–M3 (auth shell, app shell, application onboarding). **T044–T058 = M4 (intake lifecycle)** — mostly frontend over the already-shipped intake/assessment/approval backend, **plus T059–T064 = one bounded backend slice** (intake edit/withdraw/delete lifecycle parity; 2026-06-09 scope exception — see plan.md "API Gap Analysis — Milestone 4" and spec FR-033–FR-035). M4 depends on M3 (portal shell, API client, the `ApplicationWorkspace` + its shared sign-off gate — the standalone `ApprovalView` was folded into the workspace during M3, the `Badge`/`ReviewBadge` system, and an `active` application from the onboarding flow). NOTE (2026-06-09 reconciliation): M3 shipped as a single `ApplicationWorkspace` (not the original `ApplicationDetail`/`ApprovalView`/`StatusBadge`); T045/T048/T055 re-pointed accordingly.

## Format: `[ID] [P?] [Story] Description`

- **[P]**: Can run in parallel (touches different files, no dependency on an in-progress task)
- **[Story]**: Maps to user stories US1/US2/US3 from spec.md
- All portal paths are relative to `hub/portal/`; backend paths are relative to `hub/`

---

## Phase 1: Setup (Portal Scaffold)

**Purpose**: Bootstrap the Vite + React + TypeScript project and copy design-system assets so every subsequent phase has a working dev server and correct CSS.

- [X] T001 Bootstrap Vite 5 + React 18 + TypeScript 5 project at `hub/portal/` using `npm create vite@latest . -- --template react-ts`; delete the default boilerplate (`src/App.css`, `src/assets/react.svg`, `src/index.css`)
- [X] T002 Copy five CSS layer files from `specs/ui/kit/styles/` → `hub/portal/src/styles/` (tokens.css, base.css, layout.css, components.css, utilities.css); add a `src/styles/index.css` that imports them in the required order
- [X] T003 [P] Copy icon sprite and wordmark assets: `specs/ui/kit/icons/sprite.svg` → `hub/portal/public/sprite.svg`; `specs/ui/kit/assets/` → `hub/portal/public/assets/`
- [X] T004 [P] Write `hub/portal/vite.config.ts` with proxy rules: `/api/*` → `http://localhost:8000` (rewrite strips `/api`), `/auth/*` → `http://localhost:8000`, `/me` → `http://localhost:8000`
- [X] T005 [P] Write `hub/portal/tsconfig.json` and `tsconfig.app.json` with `strict: true`, path alias `@/*` → `src/*`
- [X] T006 [P] Create `hub/portal/.env.example` (`VITE_VERITY_ENV=local`, `VITE_AUTH_MODE=mock`, `VITE_API_BASE=http://localhost:8000`) and add `.env.local` to `hub/portal/.gitignore`
- [X] T007 Wire CSS layers and sprite loader in `hub/portal/src/main.tsx`: import `./styles/index.css`; inject `<link>` for the sprite or fetch and inline it via an `app.js`-style loader; render `<App />` into `#root`

**Checkpoint**: `npm run dev` starts, loads at `http://localhost:5173`, no console errors, design tokens are active (verify `--color-brand` resolves).

---

## Phase 2: Foundational (Blocking Prerequisites)

**Purpose**: Core infrastructure — API client, session context, route skeleton — that every user story depends on. Nothing in Phase 3+ can start until this is complete.

⚠️ **CRITICAL**: No user story work can begin until this phase is complete.

- [X] T008 Create `hub/portal/src/api/client.ts`: a typed `apiFetch` wrapper around `fetch` that (a) always sends credentials (`credentials: "include"`), (b) on 401 dispatches a `session-expired` event to a module-level event bus, (c) on 403 dispatches a `forbidden` event with the parsed `ApiError`, (d) returns typed response or throws `ApiError`; export typed helpers `api.get<T>`, `api.post<T>`, `api.postEmpty<T>`; types mirror `contracts/portal-api.yaml` schemas (see `data-model.md`)
- [X] T009 Create `hub/portal/src/auth/SessionContext.tsx`: define `AuthState` union type (`"loading" | "authenticated" | "unauthenticated" | "session_expired" | "forbidden" | "disabled"`); define `Principal` interface (mirror `MeResponse` from `data-model.md`); export `SessionContext` with `{principal, authState, refresh}`; `SessionProvider` calls `GET /me` on mount, subscribes to the `session-expired`/`forbidden` events from `client.ts`, sets state accordingly
- [X] T010 [P] Create `hub/portal/src/auth/useSession.ts`: thin hook over `SessionContext` — returns `{principal, authState, isAuthenticated, hasRole(role: string), canDo(action: string)}`; `canDo` checks against the static role→action map (derived from `research.md` §6)
- [X] T011 [P] Create `hub/portal/src/auth/ProtectedRoute.tsx`: wraps `<Outlet />`; if `authState === "loading"` render a fullscreen spinner; if `"unauthenticated"` redirect to `/signin?next=<encoded-pathname>`; otherwise render `<Outlet />`
- [X] T012 Create `hub/portal/src/App.tsx`: define the full route table using React Router v6 `createBrowserRouter`; public routes: `/signin`, `/auth/callback`; authenticated routes (wrapped in `ProtectedRoute`): `/` (Landing), `/applications`, `/applications/new`, `/applications/:id`, `/approvals/:id`; wrap the tree in `<SessionProvider>`; render `<RouterProvider>`
- [X] T013 Add Starlette `SessionMiddleware` to `hub/src/verity/hub/app.py` using `VERITY_SESSION_SECRET` from `Settings`; confirm existing tests still pass with `hub/.venv/bin/pytest hub/tests/ -x -q`

**Checkpoint**: `npm run dev` renders a white page at `/` (ProtectedRoute redirects to `/signin`; the `/signin` route is not yet implemented — a React Router 404 is expected and correct). API client module imports without TypeScript errors (`npm run build --noEmit`).

---

## Phase 3: User Story 1 — Sign in and land in Verity (Priority: P1) 🎯 MVP

**Goal**: A user can sign in (Entra OIDC or local-dev mock), land on the application, and see their identity — or be shown the appropriate fail-closed takeover screen if their session is expired, access denied, or account disabled.

**Independent Test**: Start hub with `VERITY_AUTH_MODE=mock VERITY_ENV=local`. Navigate to `http://localhost:5173`. Assert redirect to `/signin`. The mock-auth amber card is visible. Click "Continue as Local Dev". Assert: redirect to `/`, display name "Local Dev" visible somewhere on the page (stub landing is fine), no console errors.

### Backend additions for US1 (must precede frontend integration)

> **Implementation note (2026-06-05):** T014/T015 (Entra `/auth/login` + `/auth/callback`) are
> implemented as **honest scaffolds** — they redirect to `/signin` rather than running the full
> PKCE/token-exchange/ID-token-validation flow. Real Entra OIDC is **deferred** (needs a dev-tenant
> registration + the still-stubbed `EntraAuthenticator`); **mock auth (T016) is the working
> first-login path** for now. T016–T018 are fully implemented. See `hub/src/verity/hub/auth/session.py`.

- [X] T014 Create `hub/src/verity/hub/auth/session.py` with `GET /auth/login`: mint `state` (32-byte URL-safe random), `nonce` (32-byte), PKCE `code_verifier`/`code_challenge` (S256); store in session (`request.session`); 302 → Entra `/authorize` with `response_type=code`, `client_id`, `redirect_uri`, `scope=openid profile email`, `state`, `nonce`, `code_challenge`, `code_challenge_method=S256`; read Entra config from `Settings` (`tenant_id`, `client_id`)
- [X] T015 [P] Add `GET /auth/callback` to `hub/src/verity/hub/auth/session.py`: verify `state` matches session (single-use: delete on first read); if `error` param present → clear session, redirect to `/signin`; exchange `code` via `/token` endpoint (PKCE public client locally); validate ID token per FR-004 (sig RS256, `iss`, `aud`, `tid`, `exp`, `nonce`); call existing `provisioning.py` JIT upsert; store `actor_id` + `session_epoch` in `request.session`; 302 → allow-listed `next` or `/`
- [X] T016 [P] Add `POST /auth/mock` to `hub/src/verity/hub/auth/session.py`: guard: return 404 if `settings.auth_mode != "mock"` or `settings.env != "local"`; call existing `provisioning.py` with the configured synthetic principal (`mock_microsoft_oid`, `mock_tenant_id`, `mock_display_name`); store `actor_id` in `request.session`; return `{"ok": true}`
- [X] T017 [P] Add `POST /auth/logout` to `hub/src/verity/hub/auth/session.py`: clear `request.session`; return `{"ok": true}`
- [X] T018 Extend `GET /me` in `hub/src/verity/hub/app.py`: add `email` (from `principal.email`) and `app_team_roles` (new DB query joining `actor_app_team_role_grant` → `application`) to the response; add `is_mock` flag (true when `settings.auth_mode == "mock"`); mount `session.py` router in `create_app()`

### Frontend for US1

- [X] T019 [US1] Create `hub/portal/src/pages/SignIn.tsx`: render the centred auth card matching `specs/ui/kit/pages/signin.html` — Verity wordmark (theme-aware: `wordmark--light`/`wordmark--dark` swap), "Sign in with Microsoft" primary button navigates to `/auth/login`; render the mock-auth section (amber card, divider, "Continue as Local Dev" button that POSTs to `/auth/mock` then navigates to the `next` param or `/`) only when `import.meta.env.VITE_AUTH_MODE === "mock"` AND `import.meta.env.VITE_VERITY_ENV === "local"` — no DOM presence otherwise
- [X] T020 [P] [US1] Create `hub/portal/src/pages/AuthCallback.tsx`: on mount call `GET /auth/callback?${window.location.search.slice(1)}`; show a fullscreen loading spinner while in flight; on success call `session.refresh()` then navigate to allow-listed `next` (or `/`); on error navigate to `/signin`; no visible UI beyond loading state
- [X] T021 [P] [US1] Create `hub/portal/src/pages/AuthStatePage.tsx`: accept a `variant: "session_expired" | "forbidden" | "disabled"` prop; render the matching full-screen takeover card from `specs/ui/kit/pages/auth-states.html` — correct icon (`#i-recent` / `#i-lock` / `#i-state-deprecated`), status code label, title, body copy (role name interpolated for `forbidden`), and action button(s); export three named wrappers `SessionExpiredPage`, `ForbiddenPage`, `DisabledPage`; wire them to the `authState` switch in `SessionProvider` so they overlay any route when triggered
- [X] T022 [P] [US1] Create `hub/portal/src/shell/AccountMenu.tsx`: renders a dropdown off an avatar chip trigger button; shows mock-auth amber banner when `principal.is_mock`; display name + email in the header; platform role pills (`.role` brand colour) and app-team role pills (`.role--app` neutral); "Sign out" item calls `POST /auth/logout` then navigates to `/signin`; close on Escape or outside click; matches `specs/ui/kit/pages/account-menu.html`
- [X] T023 [US1] Wire US1 into `hub/portal/src/App.tsx`: add routes for `/signin` → `<SignIn />` and `/auth/callback` → `<AuthCallback />`; connect `authState` from `SessionContext` to display `<SessionExpiredPage>`, `<ForbiddenPage>`, `<DisabledPage>` as full-screen overlays (render before the router outlet when `authState` is one of those three values)

**Checkpoint**: Mock-auth sign-in flow works end-to-end. All three takeover variants visible (trigger via `authState` prop in dev). Sign-out clears session and returns to `/signin`.

---

## Phase 4: User Story 2 — Navigate the product inside the app shell (Priority: P2)

**Goal**: After sign-in a user sees the five-region app shell, can open the app launcher, toggle the account menu, and view the landing page with their display name.

**Independent Test**: Sign in via mock auth. Assert the five shell regions render (inspect DOM for `.app__rail`, `.app__sidebar`, `.app__topbar`, `.app__canvas`, `.app__statusbar`). Click the rail launcher icon; assert the modal opens with at least one app entry and a search input. Click the avatar; assert the account menu shows display name. Click sign out; assert redirect to `/signin`.

- [ ] T024 [US2] Create `hub/portal/src/shell/AppShell.tsx`: render the five CSS layout regions from `specs/ui/kit/pages/sample.html` — `app__rail`, `app__sidebar`, `app__topbar`, `app__canvas`, `app__statusbar`; accept `sidebar` slot prop for nav items; render `<Rail />`, `<Topbar />`, `<Outlet />` (into canvas), `<StatusBar />`; `AppShell` is the layout route wrapper for all authenticated routes in `App.tsx`
- [ ] T025 [P] [US2] Create `hub/portal/src/shell/Rail.tsx`: narrow left rail with launcher icon button at top (opens `AppLauncher` modal) and account-menu avatar chip at bottom; matches rail section of `sample.html`
- [ ] T026 [P] [US2] Create `hub/portal/src/shell/Sidebar.tsx`: renders navigation items for the active app section; accepts `items: {label, href, icon}[]` prop; highlights the active route via `useMatch`; collapses at the design-system breakpoint (add media query respecting `tokens.css` breakpoint token); initially renders Governance app nav: "Applications" → `/applications`
- [ ] T027 [P] [US2] Create `hub/portal/src/shell/Topbar.tsx`: Verity wordmark (theme-aware) on the left; breadcrumb trail (uses React Router `useMatches` with route `handle.crumb` data) in the centre-left; account-menu avatar chip on the right that toggles `<AccountMenu />`; matches topbar section of `account-menu.html`
- [ ] T028 [P] [US2] Create `hub/portal/src/shell/AppLauncher.tsx`: modal that opens over the shell (portal rendered, `z-index` above rail); grid of app tiles (hard-coded initially: "Governance"); search input filters the grid; close on Escape or overlay click; matches app-launcher section of `sample.html`
- [ ] T029 [US2] Create `hub/portal/src/pages/Landing.tsx`: welcome heading with `principal.display_name`; three quick-stats tiles sourced from `GET /api/dashboard/stats` (fall back to `{applications: 0, pending_approvals: 0, active_decisions: 0}` silently on 404/error); recent-decisions table (empty-state CTA "Onboard your first application → /applications/new" when empty); jump-back-in cards (empty state when none); matches `specs/ui/verity-homepage.html` and `sample.html` canvas
- [ ] T030 [US2] Update `hub/portal/src/App.tsx`: wrap all authenticated routes in `<AppShell />`; pass Governance sidebar items to `AppShell`; confirm `/` renders `<Landing />` inside the shell
- [ ] T031 [P] [US2] Add FastAPI `StaticFiles` mount in `hub/src/verity/hub/app.py`: serve `hub/portal/dist/` at `/` when `portal/dist/index.html` exists (guard with `os.path.exists`); ensure API routes take priority over the static catch-all; add `hub/portal/dist/` to `.gitignore`

**Checkpoint**: Full shell renders after mock sign-in. Landing page shows "Welcome, Local Dev". App launcher opens/closes. Account menu shows roles. Sign-out works.

---

## Phase 5: User Story 3 — Browse and onboard an application (Priority: P3)

> **Shipped reconciliation (2026-06-09):** T032–T037 below describe the original M3 plan (separate
> `ApplicationDetail` / `ApprovalView` / `StatusBadge` / read-only modal / 4 tabs). M3 actually
> shipped as a single **`ApplicationWorkspace`** (identity band · Compliance/Ownership tabs · Risk
> Profile + Governance & Approval rail · derived history) with create/view/approve modes, the
> reference-driven `Badge`/`ReviewBadge`, a **tab-gate** (not scroll-gate), and the requester
> cancel / app-team delete / edit-&-resubmit remediation (001 FR-IN-015a). Read T032–T037 as the
> historical plan; the live FRs (FR-014–020) and M4 tasks reflect the shipped surface.

**Goal**: A user with `ai_governance` role can view the application registry, onboard a new application through the workspace create mode, and an approver can record a sign-off decision in the workspace governance rail.

**Independent Test**: Mock-auth with `ai_governance` role (set `VERITY_MOCK_PLATFORM_ROLES=ai_governance,viewer`). Navigate to `/applications`. Assert registry table renders. Click "Onboard application". Complete all four steps. Assert `POST /api/applications` fires. Switch mock role to `security` (signoff-capable). Find the pending application → click to open → submit for approval → navigate to approval view → scroll → click "Approve" → assert `POST /api/approvals/{id}/signoff` fires with `decision_code: "approved"`.

- [ ] T032 [US3] Create `hub/portal/src/pages/applications/ApplicationsList.tsx`: fetch `GET /api/applications`; render a data table with columns `code`, `name`, `status` (StatusBadge component — see T033), `business_owner_actor_id`, `created_at`; real-time client-side search over `name` and `code`; "Onboard application" button visible only when `canDo("onboard_application")`; clicking a non-stakeholder row opens a read-only modal (inline, no route change) showing identity, ownership, compliance perimeter, status; empty state with "No applications yet" and "Onboard application" CTA; matches `specs/ui/kit/pages/applications.html`
- [ ] T033 [US3] Create `hub/portal/src/components/StatusBadge.tsx` and `hub/portal/src/components/FlowIndicator.tsx`: `StatusBadge` maps `application_status_code` to the correct pill colour token (pending/pending_approval → warning, active → positive, suspended/retired → neutral); `FlowIndicator` renders the multi-step progress strip from `specs/ui/kit/pages/flows.html` — accepts `steps: string[]` and `current: number`
- [ ] T034 [US3] Create `hub/portal/src/pages/applications/OnboardForm.tsx`: four-step form (Step 1: Identity — code TLA, name, description; Step 2: Ownership — business owner, line of business, data classification; Step 3: Compliance Perimeter — frameworks, domains, jurisdictions, attestations; Step 4: Review + submit); `<FlowIndicator>` at top reflects current step; step advance validates required fields (inline errors, no advance on invalid); "Discard changes?" confirmation modal when navigating away with `dirty = true`; final submit calls `POST /api/applications`; on 201 navigate to `/applications` with a success toast placeholder; matches `specs/ui/kit/pages/onboard-application.html`
- [ ] T035 [P] [US3] Create `hub/portal/src/pages/applications/ApprovalView.tsx`: fetch `GET /api/approvals/:id` (the kind-agnostic `ApprovalRequest` — `request_kind_code`, `required_roles[]`, `signoffs[]`); render read-only composed proposal + quorum progress (which `required_roles` have signed); action buttons disabled until a `scrolled_to_end` state becomes true (`IntersectionObserver` on a bottom sentinel). **Make the view kind-aware** (it is reused by M4): "Approve" calls `POST /api/approvals/:id/signoff` with `{decision_code: "approved"}`; the negative action is per-kind — onboarding shows "Return for revision" → `{decision_code: "requested_changes"}`, intake (`kind=intake`) shows "Reject" → `{decision_code: "rejected"}` (NO `returned_for_revision` code exists). On success navigate back (registry for onboarding, intake detail for intake); matches `specs/ui/kit/pages/onboard-approval.html`
- [ ] T036 [P] [US3] Create `hub/portal/src/pages/applications/ApplicationDetail.tsx`: fetch `GET /api/applications/:id`; render four tabs — Overview (name, code, description, owner, status), Compliance Perimeter (frameworks, domains, jurisdictions, attestations), Use Cases (empty state with CTA "Add use case — coming soon"), Team (app-team role grants from `principal.app_team_roles` filtered by this application); tab switching is client-side (no navigation); matches `specs/ui/kit/pages/application-detail.html`
- [ ] T037 [US3] Update `hub/portal/src/App.tsx`: add routes for `/applications` → `<ApplicationsList />`, `/applications/new` → `<OnboardForm />` (within shell), `/applications/:id` → `<ApplicationDetail />`, `/approvals/:id` → `<ApprovalView />`; confirm all routes render inside `<AppShell />`
- [ ] T038 [P] [US3] Add `GET /dashboard/stats` endpoint to `hub/src/verity/hub/app.py` (or a new `hub/src/verity/hub/stats/router.py`): returns `{applications: int, pending_approvals: int, active_decisions: int}` via three COUNT queries; requires `view` action; the landing page silently falls back to zeros if this endpoint is absent (already handled in T029)

**Checkpoint**: Full onboarding flow works end-to-end with mock auth. Registry → workspace create mode → submit → workspace governance rail sign-off → application shows as `active` in registry → workspace renders identity band + Compliance/Ownership tabs + Risk Profile / Governance rail.

---

## Phase 6: Polish & Cross-Cutting Concerns

**Purpose**: Empty states, WCAG verification, responsive breakpoints, and theme validation — concerns that cut across all three user stories.

- [ ] T039 Audit all screens for empty states: verify that every page in scope renders a non-blank state when data is absent — registry empty list, landing zero stats, landing no recent decisions, detail page no use cases, account menu no app-team roles; fix any blank-canvas gaps found; every empty state must include a CTA or explanatory copy per design system §8
- [ ] T040 [P] WCAG AA contrast audit: open each screen (`/signin`, auth-state variants, shell+landing, registry, onboard form, approval view, detail) in both light and dark mode for all three themes (`data-theme` = default / slate / warm on `<html>`); verify contrast ratios using the browser devtools accessibility panel; fix any failing token assignments in `hub/portal/src/styles/tokens.css` (and propagate back to `specs/ui/kit/styles/tokens.css` as the source)
- [ ] T041 [P] Responsive check: verify sign-in and auth-state pages render correctly at 375 px viewport; verify the app shell sidebar collapses at the design-system breakpoint; verify the onboard form and approval view are scrollable and not clipped at 375 px; fix any layout issues in `hub/portal/src/styles/layout.css` (propagate back to source)
- [ ] T042 [P] Theme smoke-test: add a dev-only theme switcher widget (rendered only when `VITE_VERITY_ENV=local`) to the app shell statusbar that cycles `data-theme` values and toggles `.dark`; confirm no component-level style changes are needed for any theme; remove the widget from production builds
- [ ] T043 Update `specs/002-ui-shell-auth-onboarding/quickstart.md` with any deviations discovered during implementation (actual bootstrap steps, env var names, proxy config, known issues)

---

# ════════════════════════════════════════════
# MILESTONE 4 — Intake lifecycle (mostly frontend; + one backend parity slice, Phase 6B)
# ════════════════════════════════════════════

## Phase 6B: M4 Backend Lifecycle Parity (2026-06-09 scope exception) — DONE

**Goal**: Give the intake lifecycle the same requester/app-team affordances as application onboarding (FR-033–FR-035), so the portal UX is familiar. Mirrors the application edit/withdraw/delete one-to-one. (Numbered after the M4 frontend tasks but **built first**, since the frontend consumes it.) Validation: `pytest` (14 new tests; 52 passed total).

- [X] T059 Add intake lifecycle SQL to `hub/db/queries/intake.sql` + `intake_approval.sql`: `update_intake` (status-guarded to revisable states), `get_pending_intake_approval`, `cancel_pending_intake_approvals`, and delete cascade (`delete_intake_signoffs` → `delete_intake_approvals` → `delete_intake`; requirements cascade via FK; audit left intact)
- [X] T060 Add the `delete_intake` action cell to `hub/src/verity/hub/auth/matrix.py` = `{business_owner, ai_governance, security}` (mirrors `delete_application`); edit/withdraw reuse `edit_intake`
- [X] T061 Add `IntakeConflict`, `update_intake`, `withdraw_intake`, `delete_intake` to `hub/src/verity/hub/intake/service.py` (revisable = `{proposed, in_review, impact_assessment}`; locked = everything else); mirrors `application.service`
- [X] T062 Add `PUT /intakes/{id}`, `POST /intakes/{id}/withdraw`, `DELETE /intakes/{id}` to `hub/src/verity/hub/intake/router.py` (action-gated, 404/409 mapping mirrors the application router)
- [X] T063 Sign-off parity in `hub/src/verity/hub/intake_approval/service.py`: a `requested_changes` decision closes the request like `rejected` (no deadlock) so the shared gate offers Approve / Request changes / Reject for `kind=intake`
- [X] T064 Tests: `hub/tests/verity/hub/intake/test_intake_lifecycle.py` (edit/edit-after-reject/locked-409/viewer-403; withdraw cancels + re-submit/no-open-409/viewer-403; delete cascade requirements + approvals/signoffs/locked-409/author-without-delete-403/404) + `requested_changes` close test; extend `contracts/portal-api.yaml`

---

# ════════════════════════════════════════════

## Phase 7: User Story 4 — Create an intake under an application (Priority: P4)

**Goal**: From an `active` application, an authoring user creates an intake, sees it on the application's Use Cases tab, and lands on the intake detail page where status, requirements, and assessment progress are visible.

**Independent Test**: Mock-auth with an authoring role (`VERITY_MOCK_PLATFORM_ROLES=engineer`). Open an `active` application → Use Cases tab → "New intake" → enter a title → submit → assert `POST /api/applications/{application_id}/intakes` fires and `/intakes/{id}` renders with status `proposed`. Add a requirement → assert `POST /api/intakes/{id}/requirements` fires and it appears in the list.

- [ ] T044 [P] [US4] Add intake + requirement TypeScript types to `hub/portal/src/api/types.ts` (or extend the client types): `Intake`, `IntakeCreate`, `Requirement`, `RequirementCreate`, `Intake` status union — mirror `data-model.md` §8–9 and `contracts/portal-api.yaml` (field names verbatim)
- [ ] T045 [P] [US4] Intake status + risk-tier badges on the **reference-driven badge system** (`StatusBadge` was removed in M3 — use `Badge`/`ReviewBadge` + `/reference/codes`): seed `metadata.tone` for `reference.intake_status` (proposed/in_review/approved/rejected/retired) so `<Badge table="intake_status">` colours correctly, and add a `RiskTierBadge` (high/unacceptable → negative, limited → warning, minimal → positive) per `data-model.md` §13
- [ ] T046 [US4] Create `hub/portal/src/pages/intakes/IntakeCreate.tsx`: the `intake.usecase-create` form (title required, optional description); submit calls `POST /api/applications/:appId/intakes` (body `IntakeCreate`); on 201 navigate to `/intakes/{intake_id}`; "Discard changes?" guard on dirty navigate; matches the create section of `specs/ui/verity-intake-wireframe.html`
- [ ] T047 [US4] Create `hub/portal/src/pages/intakes/IntakeDetail.tsx` **mirroring `ApplicationWorkspace`'s shape** (identity band + tabs + rail + footer, for a familiar UX): fetch `GET /api/intakes/:id`; render title, intake `<Badge table="intake_status">`, `RiskTierBadge` (when tier present), requirements list (`GET /api/intakes/:id/requirements`) with an add-requirement control (`POST …/requirements`, updates list in place; requirement_kind selector ∈ business/functional/non_functional/compliance), and an assessment-progress indicator (not-started / in-progress / tier-computed). Add an **"Intake actions" footer** (NOT the rail) with **Edit & re-submit** / **Cancel request** / **Delete** — mirroring the application workspace footer (FR-033). Disable all write affordances when the intake is **locked** (status not in `{proposed, in_review, impact_assessment}`) per FR-031. Matches the detail section of `specs/ui/verity-intake-wireframe.html`
- [ ] T047a [US4] Wire the intake **footer lifecycle actions** (FR-034/FR-035), reusing the `ApplicationWorkspace` patterns: **Edit & re-submit** → an intake edit mode (prefill + `PUT /api/intakes/:id`, gated `edit_intake`); **Cancel request** → `POST /api/intakes/:id/withdraw` (shown only when a pending approval exists; `edit_intake`); **Delete** → `DELETE /api/intakes/:id` (shown only when `canDo("delete_intake")`; on success navigate to the owning application's Use cases tab). Emit `data-changed` so the sidebar/use-cases list refreshes (same event bus as M3)
- [ ] T048 [US4] Add a **Use cases** tab to `hub/portal/src/pages/applications/ApplicationWorkspace.tsx` (ApplicationDetail was replaced by the workspace in M3; add to the existing `TABS`): list the application's intakes from `GET /api/applications/:id/intakes` (title + intake `<Badge table="intake_status">`, link to `/intakes/{id}`) with an empty-state CTA; show a "New intake" CTA → `/applications/:id/intakes/new` only when `canDo("create_intake")` (FR-023)
- [ ] T049 [US4] Wire M4 routes in `hub/portal/src/App.tsx`: `/applications/:appId/intakes/new` → `<IntakeCreate />` and `/intakes/:id` → `<IntakeDetail />`, both inside `<AppShell />` + `ProtectedRoute`

**Checkpoint**: An intake can be created under an active application and viewed; requirements can be added; terminal intakes are read-only.

---

## Phase 8: User Story 5 — Capture the shipped assessment tabs + see the computed tier (Priority: P5)

**Goal**: From an intake, the user fills the two shipped tabs (AI Decision Impact, Data) and sees the system-computed risk tier + NAIC materiality with rationale. Per-tab save sends the full snapshot; only the two shipped tabs render.

**Independent Test**: Mock-auth (authoring role). Open an intake → open the assessment → complete both tabs → Save → assert `PUT /api/intakes/:id/assessment` fires with the full snapshot and the computed `ai_risk_tier_code` + materiality render. Re-open → prior answers reload (`GET /api/intakes/:id/assessment`); revisions listed (`GET …/assessment/revisions`). Assert only two tabs exist (no Security/Mitigations/Risk-Obligations tabs).

- [ ] T050 [P] [US5] Add assessment TypeScript types to `hub/portal/src/api/types.ts`: `AssessmentInput`, `AIDecisionImpact`, `DataTab`, `AssessmentView`, `Computed`, `RevisionMeta` — mirror `data-model.md` §10 (strict enums) and the contract
- [ ] T051 [US5] Create `hub/portal/src/pages/intakes/AssessmentTabs.tsx`: render **exactly two** tabs — "AI Decision Impact" (the 8 enum fields incl. nested `human_oversight`) and "Data" — and MUST NOT render Security/Mitigations/Risk-Obligations tabs (FR-026); each tab has a **Save** that issues `PUT /api/intakes/:id/assessment` with the **full** assessment snapshot (both tabs; `security_access: null`) → one revision; the response's computed tier/materiality/rationale render in a read-only summary panel; a save only succeeds once both tabs' required fields are valid (no partial PUT — research.md §12); inline validation per tab; an `auto_rejected` (unacceptable) result shows the rejected outcome and offers no submit path (FR-028)
- [ ] T052 [US5] Integrate `AssessmentTabs` into `IntakeDetail.tsx`: open-assessment affordance; reload captured answers via `GET /api/intakes/:id/assessment`; surface the revision count from `GET /api/intakes/:id/assessment/revisions`; the assessment-progress indicator reflects whether a tier has been computed

**Checkpoint**: Both shipped tabs capture; the computed tier renders from real backend computation (no mocked tier); only two tabs are present.

---

## Phase 9: User Story 6 — Submit an assessed intake + tier-quorum sign-off (Priority: P6)

**Goal**: An author submits an assessed intake (opening a `kind=intake` approval with the tier quorum); a distinct approver signs off via the **shared sign-off gate** (extracted from `ApplicationWorkspace`, reused on `IntakeDetail`); a full quorum approves the intake. Approve / Request changes / Reject (both negatives close → revisable, 2026-06-09 parity); separation of duty; allow-but-warn during review.

**Independent Test**: Author (`engineer`) opens an assessed intake → "Submit for approval" → assert `POST /api/intakes/:id/submit` fires, returns `approval_request_id` + `required_roles`, intake advances to `in_review`. Switch to a distinct quorum role (`VERITY_MOCK_PLATFORM_ROLES=business_owner,compliance,legal,model_risk,ai_governance`) → open `/approvals/{approval_request_id}` → scroll → "Approve" → assert `POST /api/approvals/:id/signoff` with `{decision_code:"approved"}`; once all required roles approve, the intake shows `approved`.

- [ ] T053 [US6] Add the submit action to `IntakeDetail.tsx`: a "Submit for approval" control disabled until a tier is computed (FR-028); calls `POST /api/intakes/:id/submit`; on 201 show the returned `required_roles` (the tier quorum) and reflect status `in_review`; map 400 (no tier) and 409 (terminal / duplicate open approval / empty `unacceptable` quorum) to inline messages. NOTE: intake submit does NOT supersede a prior open approval (it 409s) — unlike application onboarding which cancels-and-reopens (001 FR-IN-015a); surface the 409 rather than silently re-submitting
- [ ] T054 [US6] Add the **allow-but-warn** banner (FR-032) to `IntakeDetail.tsx` + `AssessmentTabs.tsx`: while `intake_status_code === "in_review"`, edits stay enabled but a banner warns that re-saving may change the computed tier and required quorum
- [ ] T055 [US6] Extract a **shared sign-off gate** from `ApplicationWorkspace`'s Governance & Approval rail (the `.appr` quorum rows + decision actions + tab-gate + SoD/comment logic) into a reusable component, and present it on `IntakeDetail` with `kind=intake` (the standalone `ApprovalView` was folded into the workspace in M3): sourced from `GET /api/approvals/:id` (resolved from the intake's open approval), shows the composed intake + quorum progress, offers the **same three decisions as onboarding — Approve / Request changes / Reject** (`decision_code` ∈ {`approved`,`requested_changes`,`rejected`}; both negatives close the request → the intake stays `in_review`/revisable for Edit & re-submit — 2026-06-09 parity, supersedes the earlier reject-only). The submitter sees the sign-off action disabled (separation of duty; backend 403 is NOT surfaced as a route-level takeover); on resolve the intake detail reflects `approved`/`rejected`. With both negatives closing the request, the gate needs **no per-kind branching** — onboarding and intake render identically
- [ ] T056 [US6] Wire navigation: from `IntakeDetail` submit → the approval view (`/approvals/:id`, route already added in T037); after approval resolves, the intake detail reflects `approved`/`rejected`

**Checkpoint**: Full intake lifecycle is demoable end-to-end with two mock roles (separation of duty); Approve / Request changes / Reject (parity with onboarding); tier quorum drives the outcome.

---

## Phase 10: M4 Polish & Cross-Cutting

- [ ] T057 [P] Audit M4 screens for empty states (no intakes on the Use Cases tab, no requirements, assessment not started) and terminal-status write-disable (no edit/submit affordances when `rejected`/`retired`); fix any blank-canvas or stuck-affordance gaps
- [ ] T058 Update `specs/002-ui-shell-auth-onboarding/quickstart.md` §10 with any M4 deviations discovered during implementation (actual field labels, validation, tier-driving answer sets)

---

## Dependencies & Execution Order

### Phase Dependencies

- **Phase 1 (Setup)**: No dependencies — start immediately
- **Phase 2 (Foundational)**: Depends on Phase 1 — **blocks all user stories**
- **Phase 3 (US1 — Auth)**: Depends on Phase 2; backend tasks T014–T018 must precede frontend tasks T019–T023
- **Phase 4 (US2 — Shell)**: Depends on Phase 3 (session context + account menu must exist)
- **Phase 5 (US3 — Onboarding)**: Depends on Phase 4 (shell layout wrapper must exist)
- **Phase 6 (Polish)**: Depends on Phase 5 complete
- **Phase 7 (US4 — Intake create)**: Depends on M3 — needs the portal shell, API client, `ApplicationWorkspace` (a Use cases tab is added by T048), the `Badge`/`ReviewBadge` system (intake badges added by T045), and an `active` application from the onboarding flow
- **Phase 8 (US5 — Assessment)**: Depends on Phase 7 (`IntakeDetail` hosts the assessment)
- **Phase 9 (US6 — Submit + sign-off)**: Depends on Phase 8 (a computed tier gates submit) and on the shared sign-off gate extracted from `ApplicationWorkspace` (T055)
- **Phase 10 (M4 Polish)**: Depends on Phase 9 complete

### Within M4 (Phases 7–9)

- T044, T045, T050 are [P] (types/badges — different files) and can be done first
- T046, T047 (US4 pages) → T048 (ApplicationWorkspace Use cases tab) → T049 (routes)
- T051 (AssessmentTabs) depends on T050 + T047; T052 integrates it into IntakeDetail
- T053/T054 extend IntakeDetail; T055 extracts the shared sign-off gate (from ApplicationWorkspace) + uses it on IntakeDetail; T056 wires navigation

### Within Phase 3 (US1)

- T014–T018 (backend) must complete before T019–T023 (frontend) can be integration-tested
- T014, T015, T016, T017 are all parallel (different endpoints in the same file)
- T018 (mount router + extend `/me`) depends on T014–T017 existing
- T019–T022 are all parallel (different components)
- T023 (wire routes in App.tsx) depends on T019–T022

### Parallel Opportunities

**Phase 1**: T002, T003, T004, T005, T006 all parallel after T001 (scaffold)

**Phase 2**: T009, T010, T011 parallel after T008; T012 depends on T009–T011; T013 is independent (backend)

**Phase 3 backend**: T014, T015, T016, T017 all parallel; T018 depends on all four

**Phase 3 frontend**: T019, T020, T021, T022 all parallel; T023 depends on all four

**Phase 4**: T025, T026, T027, T028 all parallel after T024; T029 parallel with T025–T028; T030 depends on T024–T029; T031 independent (backend)

**Phase 5**: T033 parallel with T032; T035, T036 parallel with T034; T037 depends on T032–T036; T038 independent (backend)

---

## Parallel Example: Phase 3 (US1 Frontend)

```text
After T014–T018 (backend) are merged:

  Parallel batch A (independent components):
    T019  SignIn.tsx
    T020  AuthCallback.tsx
    T021  AuthStatePage.tsx
    T022  AccountMenu.tsx

  Then:
    T023  Wire routes in App.tsx  (depends on T019–T022)
```

---

## Implementation Strategy

### MVP: User Story 1 Only

1. Complete Phase 1 (Setup)
2. Complete Phase 2 (Foundational)
3. Complete Phase 3 backend (T014–T018) → merge
4. Complete Phase 3 frontend (T019–T023) → merge
5. **STOP and VALIDATE**: mock sign-in works, account menu shows identity, all three takeover screens reachable
6. Demo-able: the product has a door you can walk through

### Incremental Delivery

- **+Phase 4** → app shell + landing page; the product has a room to stand in
- **+Phase 5** → application onboarding; the product does its first governed action
- **+Phase 6** → polish, accessibility, themes
- **+Phase 7–9 (M4)** → the full intake lifecycle (create → assess → submit → tier-quorum sign-off) over the shipped backend; the portal now covers everything the governance backend supports
- **+Phase 10** → M4 polish (empty states, terminal-status guards)

**M4 demo milestone**: after Phase 9, the product demonstrates the entire intake story end-to-end with mock auth and two roles (separation of duty) — no curl. This is the "loginable, clickable product over all shipped backend" target.

### Parallel Team Strategy

With two developers after Phase 2 completes:
- Developer A: Phase 3 backend (T014–T018) → Phase 3 frontend (T019–T023)
- Developer B: Can start T031 (StaticFiles mount) in parallel, then picks up Phase 4 as soon as A merges T022 (AccountMenu needed by Topbar)

---

## Notes

- Portal paths use `@/` alias (configured in tsconfig) for imports: `import { useSession } from "@/auth/useSession"`
- All API calls use `apiFetch` from `@/api/client` — never raw `fetch` directly in components
- BEM class names in JSX must match the wireframe kit exactly (e.g., `app__rail`, `btn btn--primary btn--lg`)
- Never add a CSS custom property in a component file; add to `hub/portal/src/styles/tokens.css` and propagate back to `specs/ui/kit/styles/tokens.css`
- Commit after each checkpoint — each phase produces a demonstrable, non-broken state
