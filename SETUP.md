# Verity v2 — Project Setup

How to set up Verity v2 on a new laptop, where the legacy (v1) code lives, and how the
two coexist. v1 is **reference only** and is never edited.

---

## 1. Target layout

Everything sits under `~/projects/`:

```
~/projects/
  verity_legacy/          # frozen v1, READ-ONLY reference (tag: v1-final)
  verity/                 # this repo — all active v2 work
  verity.code-workspace   # VSCode multi-root file (open THIS in VSCode)
```

`verity_legacy` and `verity` are **siblings**. That is what makes relative paths
(`../verity_legacy/...`) resolve and survive being moved to another machine.

---

## 2. Freeze v1 (once, on the machine that has v1 today)

Pin v1 so "legacy" is a fixed point, not a moving target:

```bash
cd /path/to/verity_uw          # the current v1 working copy
git tag v1-final               # name today's commit
git push --tags                # only if v1 has a remote
```

`git tag` attaches a permanent label to the current commit so it can always be
reproduced exactly. Nothing is changed by this.

---

## 3. New-laptop setup, step by step

Run these on the new laptop. Each step says what it does.

```bash
# 3.1 — create the projects root
mkdir -p ~/projects && cd ~/projects

# 3.2 — bring in the frozen v1 as read-only reference
git clone <your-old-repo-url> verity_legacy   # clone v1
cd verity_legacy
git checkout v1-final                          # pin to the frozen tag (detached HEAD = clearly read-only)
cd ..
#   No remote for v1? Instead copy the v1 folder here as verity_legacy/ and simply never commit into it.

# 3.3 — get verity (this repo)
git clone <your-v2-repo-url> verity            # if v2 already has a remote
#   First time / no remote yet? See section 4 to create it.
cd verity

# 3.4 — Python environment (project rule: always a project-local venv, never global)
python3 -m venv .venv
source .venv/bin/activate
#   install deps once a pyproject/requirements exists:
#   pip install -e .

cd ..
```

Then open the workspace (next section) and you're ready.

---

## 4. First-time creation of the verity repo (only if it doesn't exist yet)

```bash
cd ~/projects
mkdir verity && cd verity
git init

# spec-first skeleton
mkdir -p specs/adrs specs/components specs/features specs/contracts specs/schema \
         tests/acceptance services k8s docs

# carry the v1 schema in as the REFERENCE INPUT for hardening (see ADR-0005)
cp ../verity_legacy/verity/src/verity/db/schema*.sql specs/schema/

git add .
git commit -m "chore: seed v2 spec tree"
```

> The current draft specs (ADR-0001..0005, the binding-grammar contract, and the
> equity-research feature spec) already exist under `specs/` — carry them over with the
> repo. They are small.

---

## 5. VSCode multi-root workspace

Create `~/projects/verity.code-workspace`:

```json
{
  "folders": [
    { "path": "verity",        "name": "v2 (active)" },
    { "path": "verity_legacy", "name": "v1 (reference, read-only)" }
  ],
  "settings": {
    "files.readonlyInclude": { "**/verity_legacy/**": true },
    "python.defaultInterpreterPath": "verity/.venv/bin/python"
  }
}
```

Open it with **File → Open Workspace from File…**. Two effects:
- Both trees are visible in one window, so `../verity_legacy/...` references resolve.
- `files.readonlyInclude` makes VSCode **refuse edits to `verity_legacy`** — a guardrail
  so reference code is never changed by accident.

---

## 6. Referencing legacy from v2

- **In specs/docs:** link with relative paths, e.g.
  `../verity_legacy/verity/src/verity/db/queries/hitl_override.sql`. Every v2 component
  spec carries a "Derived from v1" section linking the exact v1 file(s) **and** the v1
  test(s) that prove the behavior — this is the traceability that prevents lost nuance.
- **In code:** do **not** import from `verity_legacy`. It is reference to read, not a
  dependency to call. v2 code is written against specs; v1 is consulted, then closed.

---

## 7. Ground rules (recap)

- `verity_legacy` is frozen at `v1-final`, read-only, never edited.
- The schema is **hardened**, not copied verbatim (ADR-0005); v1 schema is the input.
- The harness talks to governance **via API only** (ADR-0003).
- Bindings are **Source Binding / Target Binding**, uniform across tasks and agents;
  tools and MCP are agent-only (`specs/contracts/binding-grammar.md`).
- Build the equity-research slice first; full 195-API parity is a committed later phase.
- Always use the project-local `.venv`; never install globally.
