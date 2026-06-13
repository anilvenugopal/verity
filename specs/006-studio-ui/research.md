# Research: Studio — Authoring Canvas (006)

All technical questions were resolved analytically from the existing codebase — no external research required.

## Finding 1 — LCS algorithm for block diff

**Decision**: O(mn) LCS on `PromptBlock[]`, comparing by `(kind, content fields)` — excluding the ephemeral `id` field. Output: `DiffEntry[]` with status `added | removed | unchanged`.

**Rationale**: Sequences are short (< 50 blocks). ~40 lines of TypeScript. No library dependency.

**Location**: `hub/portal/src/pages/registry/studio/lcs.ts`

---

## Finding 2 — Panel resize

**Decision**: CSS `grid-template-columns` driven by CSS custom properties (`--lib-w`, `--props-w`). Drag handle updates via `document.documentElement.style.setProperty` in `mousemove` handler — no React re-renders during drag. Clamp: 140px–400px per panel.

**Rationale**: Zero dependencies; GPU-composited layout updates.

---

## Finding 3 — Client-side compileBlocks

**Decision**: Pure TypeScript function mirroring backend `compile_blocks`:
- prose → `block.text`
- var → `{block.name}`
- list → `1. item\n2. item\n...`
- table → markdown table
- code → `` ```lang\ncode\n``` ``

**Rationale**: Live preview (FR-ST-014) requires immediate re-computation on every edit. API round-trip per keystroke is unnecessary. Algorithm is trivial and documented.

---

## Finding 4 — Semver entry dialog

**Decision**: Native `<dialog>` element. Client-side validation: `/^\d+\.\d+\.\d+(-[\w.]+)?(\+[\w.]+)?$/`. Backend enforces uniqueness (409 on duplicate).

---

## Finding 5 — Latest version detection

**Decision**: Compare `prompt_version_id` to `prompt.latest_version_id` from `GET /api/registry/prompts/:id` (PromptSummary). Match → editable; mismatch → read-only.

---

## Finding 6 — No new API contracts needed

All endpoints already exist in the 005 registry API. No new backend work. See plan.md Phase 1 table for the full endpoint list.
