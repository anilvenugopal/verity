# Verity v2 — Icon Kit

The single source of truth for every meaning-bearing icon in Verity v2. Built on
[Lucide](https://lucide.dev) (ISC). 94 semantic icons across 13 categories, covering all
navigation targets and every label-bearing icon called for in
[`../../design-system.md`](../../design-system.md) (§6 badges/callouts, §7 nav, §9 block
types, §10 canvas, §11 diff, §12 metrics, §13 triage).

## Files

| File | Role |
|---|---|
| `icons.json` | **Source of truth.** Semantic id → chosen Lucide glyph, alternatives, label, usage, review status. Hand-edited. |
| `build-icons.mjs` | Fetches the glyphs and generates `sprite.svg` + `catalog.html`. Run after any `icons.json` edit. |
| `apply-review.mjs` | Folds an exported `icon-review.json` back into `icons.json` (sets primary, preserves alts, stamps status). |
| `sprite.svg` | **Production artifact.** One `<symbol id="i-<id>">` per semantic id. Do not hand-edit — regenerated. |
| `catalog.html` | Browsable review tool: alternatives, live conflict flags, approve/change/review + notes, JSON export. Regenerated. |
| `icon-review.json` | Provenance: the review round that produced the current choices. |

## Using an icon in a page

Reference the **semantic id**, never the raw Lucide name — swapping a glyph is then a
one-line edit in `icons.json`.

```html
<!-- once per page: inline the sprite, or load it -->
<svg style="display:none"><use href="/kit/icons/sprite.svg#i-app-studio"></use></svg>

<!-- anywhere an icon is needed -->
<svg class="icon" aria-hidden="true"><use href="#i-app-studio"></use></svg>
```

Add `aria-label` on the **parent button** when the icon stands alone (per design-system §16).
The `.icon` class sets size + `currentColor`; the sprite carries Lucide's stroke attributes,
so the icon inherits text color automatically (works in light and dark mode).

> Note: cross-file `<use href="sprite.svg#...">` is blocked under `file://` (CORS). Serve
> over HTTP, or inline the sprite into the page — which is what `catalog.html` does.

## Adding or changing an icon

1. Edit `icons.json` — add an entry (`id`, `lucide`, `alt`, `label`, `usage`) or change a `lucide`.
2. `node build-icons.mjs` — refetches and regenerates the sprite + catalog.
3. Open the catalog to eyeball it. The build prints any **glyph reuse** (same glyph on two ids).

To run another visual review round: open `catalog.html`, make choices, **Export review**,
save the JSON as `icon-review.json`, then `node apply-review.mjs && node build-icons.mjs`.

## Conflict policy

The build flags every glyph used by more than one semantic id. Two kinds:

- **Same-concept reuse — allowed.** One concept appearing in two places (e.g. `wrench` for
  the canvas *Tools section* and the *Tools library*; `play` for *run*; `message-square-text`
  for *prompt* in section/library/registry). Intentional.
- **Cross-meaning collision — avoid.** Two genuinely different meanings on one glyph. Resolve
  by choosing a distinct alternative.

Current intentional reuses (8): `triangle-alert`, `info`, `circle-check` (materiality tier ≈
matching callout — design-system shares palette across these axes); `plus` (add ≈ diff-added);
`message-square-text`, `wrench`, `workflow`, `play` (one concept, two locations).

## Provenance

- Icon set: `lucide-static` v1.17.0, pinned in `icons.json` (`meta.iconSetVersion`).
- Glyphs fetched from jsDelivr at build time; nothing else is vendored.
