# Tasks: UI Shell, Auth & Application Onboarding

**Input**: Design documents from `specs/002-ui-shell-auth-onboarding/`

**Prerequisites**: plan.md ✅ · spec.md ✅ · research.md ✅ · data-model.md ✅ · contracts/portal-api.yaml ✅

**Tests**: No test tasks are generated — not requested in the spec. Vitest/RTL setup is scaffolded in Phase 1 for later use.

**Organization**: Tasks are grouped by user story. US1 (auth) is the blocker for US2 (shell), which is the blocker for US3 (onboarding). Each phase is independently deployable and demonstrable.

## Format: `[ID] [P?] [Story] Description`

- **[P]**: Can run in parallel (touches different files, no dependency on an in-progress task)
- **[Story]**: Maps to user stories US1/US2/US3 from spec.md
- All portal paths are relative to `hub/portal/`; backend paths are relative to `hub/`

---

## Phase 1: Setup (Portal Scaffold)

**Purpose**: Bootstrap the Vite + React + TypeScript project and copy design-system assets so every subsequent phase has a working dev server and correct CSS.

- [ ] T001 Bootstrap Vite 5 + React 18 + TypeScript 5 project at `hub/portal/` using `npm create vite@latest . -- --template react-ts`; delete the default boilerplate (`src/App.css`, `src/assets/react.svg`, `src/index.css`)
- [ ] T002 Copy five CSS layer files from `specs/ui/kit/styles/` → `hub/portal/src/styles/` (tokens.css, base.css, layout.css, components.css, utilities.css); add a `src/styles/index.css` that imports them in the required order
- [ ] T003 [P] Copy icon sprite and wordmark assets: `specs/ui/kit/icons/sprite.svg` → `hub/portal/public/sprite.svg`; `specs/ui/kit/assets/` → `hub/portal/public/assets/`
- [ ] T004 [P] Write `hub/portal/vite.config.ts` with proxy rules: `/api/*` → `http://localhost:8000` (rewrite strips `/api`), `/auth/*` → `http://localhost:8000`, `/me` → `http://localhost:8000`
- [ ] T005 [P] Write `hub/portal/tsconfig.json` and `tsconfig.app.json` with `strict: true`, path alias `@/*` → `src/*`
- [ ] T006 [P] Create `hub/portal/.env.example` (`VITE_VERITY_ENV=local`, `VITE_AUTH_MODE=mock`, `VITE_API_BASE=http://localhost:8000`) and add `.env.local` to `hub/portal/.gitignore`
- [ ] T007 Wire CSS layers and sprite loader in `hub/portal/src/main.tsx`: import `./styles/index.css`; inject `<link>` for the sprite or fetch and inline it via an `app.js`-style loader; render `<App />` into `#root`

**Checkpoint**: `npm run dev` starts, loads at `http://localhost:5173`, no console errors, design tokens are active (verify `--color-brand` resolves).

---

## Phase 2: Foundational (Blocking Prerequisites)

**Purpose**: Core infrastructure — API client, session context, route skeleton — that every user story depends on. Nothing in Phase 3+ can start until this is complete.

⚠️ **CRITICAL**: No user story work can begin until this phase is complete.

- [ ] T008 Create `hub/portal/src/api/client.ts`: a typed `apiFetch` wrapper around `fetch` that (a) always sends credentials (`credentials: "include"`), (b) on 401 dispatches a `session-expired` event to a module-level event bus, (c) on 403 dispatches a `forbidden` event with the parsed `ApiError`, (d) returns typed response or throws `ApiError`; export typed helpers `api.get<T>`, `api.post<T>`, `api.postEmpty<T>`; types mirror `contracts/portal-api.yaml` schemas (see `data-model.md`)
- [ ] T009 Create `hub/portal/src/auth/SessionContext.tsx`: define `AuthState` union type (`"loading" | "authenticated" | "unauthenticated" | "session_expired" | "forbidden" | "disabled"`); define `Principal` interface (mirror `MeResponse` from `data-model.md`); export `SessionContext` with `{principal, authState, refresh}`; `SessionProvider` calls `GET /me` on mount, subscribes to the `session-expired`/`forbidden` events from `client.ts`, sets state accordingly
- [ ] T010 [P] Create `hub/portal/src/auth/useSession.ts`: thin hook over `SessionContext` — returns `{principal, authState, isAuthenticated, hasRole(role: string), canDo(action: string)}`; `canDo` checks against the static role→action map (derived from `research.md` §6)
- [ ] T011 [P] Create `hub/portal/src/auth/ProtectedRoute.tsx`: wraps `<Outlet />`; if `authState === "loading"` render a fullscreen spinner; if `"unauthenticated"` redirect to `/signin?next=<encoded-pathname>`; otherwise render `<Outlet />`
- [ ] T012 Create `hub/portal/src/App.tsx`: define the full route table using React Router v6 `createBrowserRouter`; public routes: `/signin`, `/auth/callback`; authenticated routes (wrapped in `ProtectedRoute`): `/` (Landing), `/applications`, `/applications/new`, `/applications/:id`, `/approvals/:id`; wrap the tree in `<SessionProvider>`; render `<RouterProvider>`
- [ ] T013 Add Starlette `SessionMiddleware` to `hub/src/verity/hub/app.py` using `VERITY_SESSION_SECRET` from `Settings`; confirm existing tests still pass with `hub/.venv/bin/pytest hub/tests/ -x -q`

**Checkpoint**: `npm run dev` renders a white page at `/` (ProtectedRoute redirects to `/signin`; the `/signin` route is not yet implemented — a React Router 404 is expected and correct). API client module imports without TypeScript errors (`npm run build --noEmit`).

---

## Phase 3: User Story 1 — Sign in and land in Verity (Priority: P1) 🎯 MVP

**Goal**: A user can sign in (Entra OIDC or local-dev mock), land on the application, and see their identity — or be shown the appropriate fail-closed takeover screen if their session is expired, access denied, or account disabled.

**Independent Test**: Start hub with `VERITY_AUTH_MODE=mock VERITY_ENV=local`. Navigate to `http://localhost:5173`. Assert redirect to `/signin`. The mock-auth amber card is visible. Click "Continue as Local Dev". Assert: redirect to `/`, display name "Local Dev" visible somewhere on the page (stub landing is fine), no console errors.

### Backend additions for US1 (must precede frontend integration)

- [ ] T014 Create `hub/src/verity/hub/auth/session.py` with `GET /auth/login`: mint `state` (32-byte URL-safe random), `nonce` (32-byte), PKCE `code_verifier`/`code_challenge` (S256); store in session (`request.session`); 302 → Entra `/authorize` with `response_type=code`, `client_id`, `redirect_uri`, `scope=openid profile email`, `state`, `nonce`, `code_challenge`, `code_challenge_method=S256`; read Entra config from `Settings` (`tenant_id`, `client_id`)
- [ ] T015 [P] Add `GET /auth/callback` to `hub/src/verity/hub/auth/session.py`: verify `state` matches session (single-use: delete on first read); if `error` param present → clear session, redirect to `/signin`; exchange `code` via `/token` endpoint (PKCE public client locally); validate ID token per FR-004 (sig RS256, `iss`, `aud`, `tid`, `exp`, `nonce`); call existing `provisioning.py` JIT upsert; store `actor_id` + `session_epoch` in `request.session`; 302 → allow-listed `next` or `/`
- [ ] T016 [P] Add `POST /auth/mock` to `hub/src/verity/hub/auth/session.py`: guard: return 404 if `settings.auth_mode != "mock"` or `settings.env != "local"`; call existing `provisioning.py` with the configured synthetic principal (`mock_microsoft_oid`, `mock_tenant_id`, `mock_display_name`); store `actor_id` in `request.session`; return `{"ok": true}`
- [ ] T017 [P] Add `POST /auth/logout` to `hub/src/verity/hub/auth/session.py`: clear `request.session`; return `{"ok": true}`
- [ ] T018 Extend `GET /me` in `hub/src/verity/hub/app.py`: add `email` (from `principal.email`) and `app_team_roles` (new DB query joining `actor_app_team_role_grant` → `application`) to the response; add `is_mock` flag (true when `settings.auth_mode == "mock"`); mount `session.py` router in `create_app()`

### Frontend for US1

- [ ] T019 [US1] Create `hub/portal/src/pages/SignIn.tsx`: render the centred auth card matching `specs/ui/kit/pages/signin.html` — Verity wordmark (theme-aware: `wordmark--light`/`wordmark--dark` swap), "Sign in with Microsoft" primary button navigates to `/auth/login`; render the mock-auth section (amber card, divider, "Continue as Local Dev" button that POSTs to `/auth/mock` then navigates to the `next` param or `/`) only when `import.meta.env.VITE_AUTH_MODE === "mock"` AND `import.meta.env.VITE_VERITY_ENV === "local"` — no DOM presence otherwise
- [ ] T020 [P] [US1] Create `hub/portal/src/pages/AuthCallback.tsx`: on mount call `GET /auth/callback?${window.location.search.slice(1)}`; show a fullscreen loading spinner while in flight; on success call `session.refresh()` then navigate to allow-listed `next` (or `/`); on error navigate to `/signin`; no visible UI beyond loading state
- [ ] T021 [P] [US1] Create `hub/portal/src/pages/AuthStatePage.tsx`: accept a `variant: "session_expired" | "forbidden" | "disabled"` prop; render the matching full-screen takeover card from `specs/ui/kit/pages/auth-states.html` — correct icon (`#i-recent` / `#i-lock` / `#i-state-deprecated`), status code label, title, body copy (role name interpolated for `forbidden`), and action button(s); export three named wrappers `SessionExpiredPage`, `ForbiddenPage`, `DisabledPage`; wire them to the `authState` switch in `SessionProvider` so they overlay any route when triggered
- [ ] T022 [P] [US1] Create `hub/portal/src/shell/AccountMenu.tsx`: renders a dropdown off an avatar chip trigger button; shows mock-auth amber banner when `principal.is_mock`; display name + email in the header; platform role pills (`.role` brand colour) and app-team role pills (`.role--app` neutral); "Sign out" item calls `POST /auth/logout` then navigates to `/signin`; close on Escape or outside click; matches `specs/ui/kit/pages/account-menu.html`
- [ ] T023 [US1] Wire US1 into `hub/portal/src/App.tsx`: add routes for `/signin` → `<SignIn />` and `/auth/callback` → `<AuthCallback />`; connect `authState` from `SessionContext` to display `<SessionExpiredPage>`, `<ForbiddenPage>`, `<DisabledPage>` as full-screen overlays (render before the router outlet when `authState` is one of those three values)

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

**Goal**: A user with `ai_governance` role can view the application registry, onboard a new application through the multi-step form, and an approver can record a sign-off decision. Application detail with four tabs is accessible for active applications.

**Independent Test**: Mock-auth with `ai_governance` role (set `VERITY_MOCK_PLATFORM_ROLES=ai_governance,viewer`). Navigate to `/applications`. Assert registry table renders. Click "Onboard application". Complete all four steps. Assert `POST /api/applications` fires. Switch mock role to `security` (signoff-capable). Find the pending application → click to open → submit for approval → navigate to approval view → scroll → click "Approve" → assert `POST /api/approvals/{id}/signoff` fires with `decision_code: "approved"`.

- [ ] T032 [US3] Create `hub/portal/src/pages/applications/ApplicationsList.tsx`: fetch `GET /api/applications`; render a data table with columns `code`, `name`, `status` (StatusBadge component — see T033), `business_owner_actor_id`, `created_at`; real-time client-side search over `name` and `code`; "Onboard application" button visible only when `canDo("onboard_application")`; clicking a non-stakeholder row opens a read-only modal (inline, no route change) showing identity, ownership, compliance perimeter, status; empty state with "No applications yet" and "Onboard application" CTA; matches `specs/ui/kit/pages/applications.html`
- [ ] T033 [US3] Create `hub/portal/src/components/StatusBadge.tsx` and `hub/portal/src/components/FlowIndicator.tsx`: `StatusBadge` maps `application_status_code` to the correct pill colour token (pending/pending_approval → warning, active → positive, suspended/retired → neutral); `FlowIndicator` renders the multi-step progress strip from `specs/ui/kit/pages/flows.html` — accepts `steps: string[]` and `current: number`
- [ ] T034 [US3] Create `hub/portal/src/pages/applications/OnboardForm.tsx`: four-step form (Step 1: Identity — code TLA, name, description; Step 2: Ownership — business owner, line of business, data classification; Step 3: Compliance Perimeter — frameworks, domains, jurisdictions, attestations; Step 4: Review + submit); `<FlowIndicator>` at top reflects current step; step advance validates required fields (inline errors, no advance on invalid); "Discard changes?" confirmation modal when navigating away with `dirty = true`; final submit calls `POST /api/applications`; on 201 navigate to `/applications` with a success toast placeholder; matches `specs/ui/kit/pages/onboard-application.html`
- [ ] T035 [P] [US3] Create `hub/portal/src/pages/applications/ApprovalView.tsx`: fetch `GET /api/approvals/:id`; render read-only composed proposal (application name, code, all fields, compliance perimeter, required signoffs list); "Approve" and "Return for revision" buttons are disabled until a `scrolled_to_end` state becomes true (set via `IntersectionObserver` on a sentinel element at the bottom of the proposal); "Approve" calls `POST /api/approvals/:id/signoff` with `{decision_code: "approved"}`; "Return" calls the same endpoint with `{decision_code: "returned_for_revision"}`; on success navigate to `/applications`; matches `specs/ui/kit/pages/onboard-approval.html`
- [ ] T036 [P] [US3] Create `hub/portal/src/pages/applications/ApplicationDetail.tsx`: fetch `GET /api/applications/:id`; render four tabs — Overview (name, code, description, owner, status), Compliance Perimeter (frameworks, domains, jurisdictions, attestations), Use Cases (empty state with CTA "Add use case — coming soon"), Team (app-team role grants from `principal.app_team_roles` filtered by this application); tab switching is client-side (no navigation); matches `specs/ui/kit/pages/application-detail.html`
- [ ] T037 [US3] Update `hub/portal/src/App.tsx`: add routes for `/applications` → `<ApplicationsList />`, `/applications/new` → `<OnboardForm />` (within shell), `/applications/:id` → `<ApplicationDetail />`, `/approvals/:id` → `<ApprovalView />`; confirm all routes render inside `<AppShell />`
- [ ] T038 [P] [US3] Add `GET /dashboard/stats` endpoint to `hub/src/verity/hub/app.py` (or a new `hub/src/verity/hub/stats/router.py`): returns `{applications: int, pending_approvals: int, active_decisions: int}` via three COUNT queries; requires `view` action; the landing page silently falls back to zeros if this endpoint is absent (already handled in T029)

**Checkpoint**: Full onboarding flow works end-to-end with mock auth. Registry → onboard form → submit → approval view → sign-off → application shows as `active` in registry → detail page renders four tabs.

---

## Phase 6: Polish & Cross-Cutting Concerns

**Purpose**: Empty states, WCAG verification, responsive breakpoints, and theme validation — concerns that cut across all three user stories.

- [ ] T039 Audit all screens for empty states: verify that every page in scope renders a non-blank state when data is absent — registry empty list, landing zero stats, landing no recent decisions, detail page no use cases, account menu no app-team roles; fix any blank-canvas gaps found; every empty state must include a CTA or explanatory copy per design system §8
- [ ] T040 [P] WCAG AA contrast audit: open each screen (`/signin`, auth-state variants, shell+landing, registry, onboard form, approval view, detail) in both light and dark mode for all three themes (`data-theme` = default / slate / warm on `<html>`); verify contrast ratios using the browser devtools accessibility panel; fix any failing token assignments in `hub/portal/src/styles/tokens.css` (and propagate back to `specs/ui/kit/styles/tokens.css` as the source)
- [ ] T041 [P] Responsive check: verify sign-in and auth-state pages render correctly at 375 px viewport; verify the app shell sidebar collapses at the design-system breakpoint; verify the onboard form and approval view are scrollable and not clipped at 375 px; fix any layout issues in `hub/portal/src/styles/layout.css` (propagate back to source)
- [ ] T042 [P] Theme smoke-test: add a dev-only theme switcher widget (rendered only when `VITE_VERITY_ENV=local`) to the app shell statusbar that cycles `data-theme` values and toggles `.dark`; confirm no component-level style changes are needed for any theme; remove the widget from production builds
- [ ] T043 Update `specs/002-ui-shell-auth-onboarding/quickstart.md` with any deviations discovered during implementation (actual bootstrap steps, env var names, proxy config, known issues)

---

## Dependencies & Execution Order

### Phase Dependencies

- **Phase 1 (Setup)**: No dependencies — start immediately
- **Phase 2 (Foundational)**: Depends on Phase 1 — **blocks all user stories**
- **Phase 3 (US1 — Auth)**: Depends on Phase 2; backend tasks T014–T018 must precede frontend tasks T019–T023
- **Phase 4 (US2 — Shell)**: Depends on Phase 3 (session context + account menu must exist)
- **Phase 5 (US3 — Onboarding)**: Depends on Phase 4 (shell layout wrapper must exist)
- **Phase 6 (Polish)**: Depends on Phase 5 complete

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
