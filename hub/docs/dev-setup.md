# Dev setup

## Python

The hub's virtualenv is at `hub/.venv/`. It is managed by `uv` — never `pip install`, never `python -m pytest` from the repo root.

**Run tests:**
```sh
./dev test              # from repo root — uses hub/.venv, streams output
./dev test --cov        # adds --cov=verity.hub --cov-report=term-missing (floor 70%)
```

Or directly from `hub/`:
```sh
cd hub
uv run pytest --tb=short
```

The `./dev` script prints which interpreter it is using before running, so you know you are not picking up system Python.

**Never do:**
- `python tools/dev.py test` (picks up system Python, which will fail with import errors)
- `pip install ...` (bypasses uv lockfile)
- `pytest` directly from repo root (wrong working directory, no venv context)

## Node / portal

The portal is a Vite + React + TypeScript app at `hub/portal/`. The Node version is pinned in `hub/portal/.nvmrc`.

```sh
cd hub/portal
nvm use               # switches to the pinned version
npm install           # first time or after package.json changes
npm run dev           # dev server at http://localhost:5173
```

**Run Vitest unit tests:**
```sh
./dev test:portal     # from repo root — prints node version, then runs vitest
```

Or directly:
```sh
cd hub/portal
npm run test          # vitest run (CI mode, exits after one pass)
npm run test -- --watch  # watch mode for TDD
```

## Both servers together

```sh
./dev up     # starts hub API (:8000) + portal (:5173) as background processes
./dev down   # stops them
./dev status # shows what's running
```

Logs go to `tools/.run/hub.log` and `tools/.run/portal.log`.

## VSCode Testing tab

Open the workspace from the **repo root** (`code .`). The workspace root has `pytest.ini` (inside `hub/`) discovered via the `python.testing.pytestPath` workspace setting, and `hub/portal/vite.config.ts` has a Vitest config block.

- **Python tests**: Configure `Python: Select Interpreter` to `hub/.venv/bin/python`. The Testing tab will then discover all `hub/tests/` pytest tests (currently 67).
- **Vitest tests**: The Vitest VS Code extension (or the built-in Jest/Vitest runner) discovers tests in `hub/portal/src/**/__tests__/`. Currently 20 tests across 4 files.

If the Testing tab shows no tests, check:
1. The Python interpreter is set to `hub/.venv/bin/python` (not system Python).
2. You are running `nvm use` so the Node version matches `.nvmrc`.

## The `noUncheckedIndexedAccess` rule

`hub/portal/tsconfig.app.json` enables `noUncheckedIndexedAccess: true`. This means every `Record<K,V>[key]` lookup returns `V | undefined` — even for keys you know are present.

**Do not revert this flag.** It exists because we have already had one production bug (`FIELDS['classification']` was missing from `assessmentCatalog.ts`) that this rule would have caught at compile time. The rule forces you to write `FIELDS[key] ?? fallback` rather than assuming the key exists.

When you add a new key to a `Record<string, T>` lookup, write a companion test (see `assessmentCatalog.test.ts` for the pattern) that asserts the key exists, so the build catches future regressions at the test layer as well as the type layer.
