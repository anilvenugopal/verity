# CSS architecture — Verity hub portal

How styling is organised, what belongs where, and how a class earns its way into the shared layers.
This is a living document — keep the **usage map** at the end current as the portal grows.

## Source of truth & the copy rule

The design-kit layers are authored once and **copied** into the portal, kept byte-identical:

```
specs/ui/kit/styles/*.css   ← source of truth (the kit)
hub/portal/src/styles/*.css ← portal copy (never diverge; change the source, then re-copy)
```

Any edit to a layer file must land in **both** copies and be verified identical
(`diff -q specs/ui/kit/styles/X.css hub/portal/src/styles/X.css`). Page-local CSS (see below) lives
only in the portal, co-located with its component, and is not part of the kit.

## The layers (cascade order)

Imported in `hub/portal/src/styles/index.css` in this order — later layers may override earlier ones:

| # | Layer | Owns | Rule of thumb |
|---|-------|------|---------------|
| 1 | `tokens.css` | CSS custom properties: colour, space, type, radius, shadow, motion. The themeable surface (`data-theme` × `.dark`). | Never hard-code a value a token already names. |
| 2 | `base.css` | Element resets and base element styling (`html`, `body`, headings, links). | No classes — element selectors only. |
| 3 | `layout.css` | App frame + layout primitives: `.app__*` regions, `.l-grid`, `.l-cluster`, `.l-spacer`. | Structure, not skin. |
| 4 | `components.css` | Reusable UI **components**: `.btn`, `.card`, `.callout`, `.chip`, `.badge` (base), `.input`/`.form-field`, `.tabs`, `.nav-item`, `.sidebar__*`, `.breadcrumb`, `[data-tooltip]`/`.tooltip`, … plus a segregated **data-element** section at the bottom. | Generic, app-agnostic, reused across ≥2 places. |
| 5 | `badges.css` | The reference-table-driven **badge system**: the closed `[data-tone]` palette + display modifiers (`.badge--quiet/--sm/--lg/--icon-only/--no-icon`). Base `.badge`/`.badge__*` stay in components.css. | Adding a reference value needs **no** new CSS. |
| 6 | `utilities.css` | Single-purpose `!important` helpers: `.u-hidden`, `.u-text-tertiary`, `.u-ml-auto`, … | Last resort; one declaration each. |

Plus one **portal-only shared** sheet (not a kit layer), imported after the layers:

- `page.css` — canvas-page composition repeated across pages: `.canvas-pad`, `.page-head`, `.section`,
  the `.kv` key-value grid, `.yn` yes/no, and the sticky `.form-actions` bar. Promote here when a
  composition is shared by ≥2 pages but is too page-shaped to be a generic component.

## Page-local CSS

Co-located with the component (`pages/applications/ApplicationsList.css`, `OnboardForm.css`,
`ApplicationWorkspace.css`). Holds **one page's** composition that isn't (yet) shared. Reuse canonical
classes first; only add page-local rules for genuinely page-specific structure. Examples today:
`.reg-grid` (registry table), `.field-grid`/`.flag-row`/`.proposer` (onboard form), `.aw-*`/`.rail-*`/
`.appr`/`.tl-*` (workspace shell — shared by create + view via import).

## What belongs where — the philosophy

Three kinds of CSS, decided by **what the rule expresses**:

1. **Core style primitive** — a generic, reusable UI element (button, card, input, tab, tooltip). Lives
   in `components.css` (or `layout.css` if it's structure). Carries no business meaning.
2. **Business-data component** — renders a specific *domain* data element (the application acronym
   chip `.tla`; the reference `.badge-{category}` family). Canonical when reused, but **segregated** —
   `.tla` sits in a clearly-commented "DATA-ELEMENT COMPONENTS" section at the bottom of
   `components.css`; badges have their own `badges.css`. A dedicated data-element home is a future TODO.
3. **Composition** — how a particular page/feature arranges primitives. Page-local by default;
   promoted to `page.css` when ≥2 pages share it.

### Promotion path (page-local → canonical)

A class earns promotion when it is **reused in ≥2 places**. The gate (high-materiality — see the team's
CSS review rule): present the rule for review, justify it against best practice, establish it as
strategic, then promote. Promotion is a **relocation, not a rewrite** — no visual change. Delete the
page-local copy in the same change; keep both kit/portal copies identical.

Worked examples:
- `.app-status` (registry) → needed by the sidebar too → became the tone-driven **badge system**.
- `.tla` (registry) → needed by the detail header → promoted to the data-element section.
- `.kv` / `.form-actions` (detail / onboard) → shared by the workspace → moved to `page.css`.

### Anti-patterns

- **No inline `style={{…}}`** for anything a class/token can express — reach for a utility or a
  reviewed class instead.
- **No hard-coded values** where a token exists.
- **No silent divergence** between the kit source and the portal copy.
- **No new layer-file rule without review** — page-local prototype first.

## Evolving usage map

Which canonical/shared classes back which surfaces. Update as the portal grows.

| Class / system | Layer | Used by |
|----------------|-------|---------|
| `.btn`, `.card`, `.callout`, `.chip`/`.chip--static`, `.input`/`.form-field`, `.empty-state` | components | everywhere |
| required-field: `.is-required`, `.input--error`, `.input-error-text` | components | OnboardForm |
| `.tabs`/`.tab`/`.tab__marker` | components | ApplicationWorkspace, OnboardForm |
| `[data-tooltip]` (CSS) | components | Rail icons |
| `.tooltip` (portal-positioned) + `useTooltip` | components | `<Badge>` |
| badge system: `.badge` + `[data-tone]` + `.badge--*` | components + badges | `<Badge>`, registry, sidebar, workspace risk profile |
| data-element: `.tla` | components (data-element §) | registry, workspace header |
| `.canvas-pad`/`.page-head`/`.section`/`.kv`/`.yn`/`.form-actions` | page.css | every canvas page |
| `.nav-item`/`.sidebar__*`/`.rail-app-icon` | layout/components | shell (Rail, Sidebar) |
| `.reg-grid` | page-local | ApplicationsList |
| `.field-grid`/`.flag-row`/`.proposer` | page-local | OnboardForm |
| `.aw-*`/`.rail-*`/`.appr*`/`.tl-*` | page-local (workspace) | ApplicationWorkspace, OnboardForm (create) |
