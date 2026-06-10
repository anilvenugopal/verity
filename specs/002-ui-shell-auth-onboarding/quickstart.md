# Quickstart: UI Shell, Auth & Application Onboarding

**Date**: 2026-06-05

Prerequisites: Node 20+, the hub backend running at `http://localhost:8000` with `VERITY_AUTH_MODE=mock VERITY_ENV=local`.

---

## 1. Bootstrap the portal project

From the repo root:

```bash
cd hub/portal
npm create vite@latest . -- --template react-ts   # if not yet bootstrapped
npm install
```

If the project already exists, just:

```bash
cd hub/portal && npm install
```

---

## 2. Copy design-system assets

Run once after bootstrap (or after a kit update):

```bash
# CSS layers
cp -r ../../specs/ui/kit/styles/* src/styles/

# Icon sprite and wordmark assets
cp ../../specs/ui/kit/icons/sprite.svg public/sprite.svg
cp -r ../../specs/ui/kit/assets public/assets/
```

These files are the source of truth. Any edit to the CSS must start in `specs/ui/kit/styles/` and be copied here — never edit `src/styles/` directly.

---

## 3. Environment variables

Create `hub/portal/.env.local` (git-ignored):

```dotenv
VITE_VERITY_ENV=local
VITE_AUTH_MODE=mock
VITE_API_BASE=http://localhost:8000
```

For Entra OIDC testing (optional, requires a dev-tenant registration):

```dotenv
VITE_VERITY_ENV=local
VITE_AUTH_MODE=entra
VITE_API_BASE=http://localhost:8000
```

---

## 4. Vite proxy (vite.config.ts)

The portal proxies API and auth calls to the hub in development:

```typescript
// hub/portal/vite.config.ts
import { defineConfig } from 'vite'
import react from '@vitejs/plugin-react'

export default defineConfig({
  plugins: [react()],
  server: {
    proxy: {
      '/api': { target: 'http://localhost:8000', rewrite: path => path.replace(/^\/api/, '') },
      '/auth': { target: 'http://localhost:8000' },
      '/me':   { target: 'http://localhost:8000' },
    }
  }
})
```

---

## 5. Run the portal

```bash
# Terminal 1 — hub backend (from hub/)
source .venv/bin/activate
VERITY_AUTH_MODE=mock VERITY_ENV=local uvicorn verity.hub.app:app --reload

# Terminal 2 — portal dev server (from hub/portal/)
npm run dev
```

Open `http://localhost:5173`. You should be redirected to `/signin`.

Click "Continue as Local Dev" → you land on the landing page as `Local Dev` with roles `security, viewer`.

---

## 6. Run portal tests

```bash
cd hub/portal
npm run test          # Vitest unit tests
npm run test:ui       # Vitest UI
```

---

## 7. Build for production

```bash
cd hub/portal
npm run build         # outputs to hub/portal/dist/
```

FastAPI serves the built dist at `/` via `StaticFiles` mount in `app.py` (added as part of M2 task).

---

## 8. Key files to know

| File | Purpose |
|---|---|
| `hub/portal/src/api/client.ts` | Typed fetch wrapper; intercepts 401/403 |
| `hub/portal/src/auth/SessionContext.tsx` | React context for `Principal \| null` |
| `hub/portal/src/auth/ProtectedRoute.tsx` | Redirects unauthenticated to `/signin` |
| `hub/portal/src/shell/AppShell.tsx` | Root layout (rail + sidebar + topbar + canvas) |
| `hub/portal/src/styles/tokens.css` | All design tokens — the only place to add/change token values |
| `specs/ui/kit/pages/` | Approved HTML wireframes — visual source of truth for every screen |
| `specs/002-ui-shell-auth-onboarding/contracts/portal-api.yaml` | OpenAPI contract for the portal-consumed API surface |
| `hub/src/verity/hub/auth/session.py` | [TO BE CREATED] OIDC + mock session endpoints |

---

## 9. Adding a new screen

1. Check the wireframe in `specs/ui/kit/pages/` first.
2. Add a route in `App.tsx`.
3. Wrap with `ProtectedRoute` if authenticated.
4. Create a page component in `src/pages/`.
5. Use BEM class names from `components.css`; use tokens from `tokens.css` via CSS custom properties.
6. Never add a `--color-*` or `--space-*` variable directly in a component file — add it to `tokens.css` first (and update `specs/ui/kit/styles/tokens.css` as the source).

---

## 10. M4 — Intake lifecycle demo flow (mock auth, end-to-end)

Demonstrates the full lifecycle, with **separation of duty** via two mock roles (the author may not sign off on their own intake). M4 added the intake lifecycle **parity backend** (`PUT /intakes/{id}` edit, `POST /intakes/{id}/withdraw`, `DELETE /intakes/{id}`, `delete_intake` action) so an intake's edit/cancel/delete mirror application onboarding; `ApprovalRequest` now exposes `opened_by_actor_id` so the portal disables the submitter's own sign-off. Reference wireframe: `specs/ui/verity-intake-wireframe.html`.

**Pre-req**: an `active` application exists (onboard one via M3, or seed one). An intake can only be created under an `active` application.

1. **Author creates + assesses** — run the hub as an authoring role:
   ```bash
   VERITY_AUTH_MODE=mock VERITY_ENV=local \
     VERITY_MOCK_MICROSOFT_OID=aaaa1111-2222-3333-4444-555566667777 \
     VERITY_MOCK_PLATFORM_ROLES=ai_governance \
     uvicorn verity.hub.app:app --reload
   ```
   In the portal: **ACTIONS → New use case** (pick an active application) — or open the active application → **Use cases** tab → **New intake** — → land on `/intakes/{id}` (status `proposed`). The detail page is flat-tabbed: **Requirements | AI Decision Impact | Data**. Fill **AI Decision Impact** (8 fixed-choice fields — decision role/domain/population/adverse impact/human oversight/reversibility/GDPR Art. 22/deployment scale) and **Data** (description, classification, PII presence, sources, sensitive categories) → **Save assessment** (Save sends the *full* snapshot from both tabs; it stays disabled until both are valid). The backend computes the tier + NAIC materiality, shown in the **Computed classification** panel and the right-rail **Risk tier**. A `high`-leaning answer set (e.g. adverse impact = coverage/claim denial, autonomous, production-wide) gives `high`.

2. **Author submits** — **Submit for approval** (right-rail Governance & approval). The intake advances to `in_review`; the gate shows the tier quorum (`high` → 5 roles). The author cannot sign off (separation of duty — the button is disabled with an explanation).

3. **Approver signs off** — restart the hub as a *distinct* quorum role (repeat for each required role, or use one principal holding several):
   ```bash
   VERITY_MOCK_MICROSOFT_OID=dddd1111-2222-3333-4444-555566667777 \
     VERITY_MOCK_PLATFORM_ROLES=business_owner,compliance,legal,model_risk,ai_governance
   ```
   Open the intake (`/intakes/{id}`, or follow `/approvals/{id}` which redirects there). The sign-off gate lives on the intake detail's **Governance & approval** rail and is **tab-gated** — open the **Assessment** tab to review before the decision buttons enable. Decisions are **Approve / Request changes / Reject** (the same shared gate as onboarding; both negatives close the request and drop the intake back to revisable for **Edit & re-submit**). Once every required role approves, the intake flips to **`approved`** (locked).

**Edge demos**: an `unacceptable`-tier assessment auto-rejects the intake (no submit path); editing while `in_review` stays enabled but shows a "re-saving may change the tier/quorum" banner; a submitter's own sign-off is disabled; the requester can **Cancel request** (withdraw the open approval → back to a revisable draft) and the app team can **Delete** a still-revisable intake (both in the intake-actions footer, mirroring the application workspace); a `rejected`/`retired` (locked) intake shows everything read-only with no edit/submit/delete affordances.

## 11. Known issues & deviations (M4 close-out QA)

- **Assessment is one sectioned form** (Decision context · Data inventory · Human oversight · Risks · Fairness), not the original two tabs — the data, oversight, risk and fairness inventories are multi-entry, and every field carries inline + `(?)` + Learn-more help (FR-026 redesign; spec/data-model §10).
- **WCAG AA contrast**: token pairs were computed against AA (4.5:1). All light-mode and most dark-mode pairs pass comfortably; two marginal dark-mode fails were fixed in `tokens.css` (propagated to `specs/ui/kit/styles/tokens.css`): base `--text-tertiary` on cards (#828BA0 → #8A93A7, 4.44 → 4.91) and warm-theme dark `--text-tertiary` (#8E8579 → #968C7F, 4.31 → 4.73). Pixel-level verification across all three themes × both modes still wants a one-time browser/devtools pass.
- **Themes are token-only**: there are **zero** hardcoded colours in component/page CSS, so no per-theme component overrides are needed (the goal of the theme smoke-test, T042). Live theme cycling (mode × palette) is available in **Preferences**, so a separate dev-only switcher widget was deliberately not added.
- **Responsive posture**: this is a **desktop-first** governance tool. The app shell sidebar collapses to rail-only at ≤1280px. Sign-in / auth-state are simple centred cards (fluid). The workspace and assessment use desktop two-column layouts and are **not** optimised for ≤~768px viewports — mobile layouts are out of scope for now.
- **Static portal serving**: the hub serves the built portal from `hub/portal/dist/` at `/` when present (`app.py` `StaticFiles` mount); in dev, Vite serves it on :5173 via the proxy in §4. `portal/dist/` is gitignored.
- **Demo data**: `./dev demo` (refresh / idempotent) seeds an active host application + use cases across the lifecycle, separate from the governed reference/core seed (see `tools/demo_seed.py`).
