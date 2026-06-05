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
