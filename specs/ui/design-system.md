# Verity v2 — UI Design System

**Version:** 1.0  
**Status:** Canonical — consult before creating, modifying, or specifying any UI  
**Reference implementation:** `verity-design-sample.html` — the approved color and component sample  
**Stack:** React + TypeScript + plain CSS custom properties (no Tailwind, no CSS-in-JS)

> This document is the single source of truth for all visual and architectural decisions in Verity v2. Claude Code, human engineers, and designers all consult this before touching any UI. When implementation and this document conflict, this document wins — or this document is updated first.

---

## 1. Aesthetic direction

Verity is a **governance platform for regulated AI**. The aesthetic is precision over warmth, authority over friendliness, clarity over decoration. The reference register is Palantir Foundry and VS Code — cool neutral surfaces, disciplined color, no chrome for its own sake.

**The first rule:** if you are reaching for a new color, you are solving the wrong problem. Reach for an icon, a weight change, a position shift, or an uppercase label first. Color encodes meaning, not sequence.

**The second rule:** every UI element must be immediately self-explanatory. Every page has a getting-started state. Every field, action, and section has contextual help. No blank screens, no mystery affordances.

**The interactive accent:** every theme has exactly **one** interactive accent — referenced through `--color-brand` (and the button-fill tokens `--btn-*`). All buttons, links, active states, and focus rings derive from it; no other hue is used for interactive affordance.

**Themes.** The accent (and, for Warm, the neutrals + status hues) is themeable via `[data-theme]` on the root, composed with `.dark`. Three palettes ship — **Gray** (default · neutral graphite accent), **Slate** (the slate-blue heritage accent, `#2C4E7E`), and **Warm** (warm stone neutrals · warm-gray accent · warm-green positive). Components reference semantic tokens only, so a theme — or a future per-customer override — is a `tokens.css` remap, never a component change. Every theme × mode must clear WCAG AA (verify with the contrast check).

---

## 2. Five-layer CSS architecture (ITCSS)

CSS is organised in exactly five files, loaded in this order. Specificity climbs predictably. Nothing in a lower layer overrides a higher one without `!important` (which lives exclusively in layer 5).

```
┌──────────────────────────────────────────────────┐
│  1. tokens.css     — design tokens (all :root)   │  zero specificity
│  2. base.css       — reset + element baseline    │  element selectors
│  3. layout.css     — app shell + layout prims    │  single class selectors
│  4. components.css — all UI components (BEM)     │  BEM class selectors
│  5. utilities.css  — single-purpose escape hatch │  !important classes
└──────────────────────────────────────────────────┘
```

**Loading order in every page — non-negotiable:**

```html
<link rel="stylesheet" href="/styles/tokens.css">
<link rel="stylesheet" href="/styles/base.css">
<link rel="stylesheet" href="/styles/layout.css">
<link rel="stylesheet" href="/styles/components.css">
<link rel="stylesheet" href="/styles/utilities.css">
```

### Layer 1 — tokens.css

All `:root { --variable }` declarations. Zero selectors. Three tiers:

**Tier 1 — primitives:** raw values, named by family and weight. Never referenced in component CSS directly.

```css
--c-blue-900: #1D3557;
--c-blue-700: #2C4E7E;   /* brand anchor */
--c-blue-600: #3B6091;
--c-blue-500: #4A72A4;
--c-blue-200: #C5D5E8;
--c-blue-100: #E0EAF4;
--c-blue-050: #EEF4FA;
```

**Tier 2 — semantic:** meaning-bound, purpose-named. What components reference.

```css
--color-brand:          var(--c-blue-700);
--color-brand-hover:    var(--c-blue-600);
--color-brand-faint:    var(--c-blue-050);
--surface-page:         var(--c-surface-0);
--text-primary:         var(--c-text-900);
```

**Tier 3 — component tokens:** only when a component needs a property that varies independently. Default to tier 2. Reach for tier 3 only when you would otherwise cascade a semantic token to one component and break all others.

```css
--badge-champion-bg:    var(--c-green-050);
--badge-deprecated-bg:  #EAECF0;
```

### Layer 2 — base.css

Element-level reset and baseline. No class selectors. No layout. No components.

Covers: `html`, `body`, `h1–h6`, `p`, `a`, `button`, `input`, `textarea`, `select`, `img`, `code`, `pre`, `table`, `hr`, `::selection`, `:focus-visible`, scrollbars, `@media (prefers-reduced-motion)`.

Key rules:
- Body: `font-family: var(--font-ui)`, `background: var(--surface-page)`, antialiased
- All form elements: `font: inherit; color: inherit; background: transparent; border: none; outline: none`
- Focus visible: `box-shadow: var(--ring-focus)` — no outline, ring only
- `[hidden]`: `display: none !important`

### Layer 3 — layout.css

Page and app structural primitives. Positions things, does not style them visually beyond positioning.

Surface composition modifiers (apply to any container, descendants inherit correct on-surface colors):

```css
.surface-page    { background: var(--surface-page); }
.surface-panel   { background: var(--surface-panel); }
.surface-nav     { background: var(--surface-nav); }
.surface-recessed{ background: var(--surface-recessed); }
```

App shell slots:
- `.app` — full viewport flex column
- `.app__topbar` — fixed height, `var(--topbar-h)`, `surface-nav`
- `.app__left-rail` — icon-only app rail, `var(--rail-w)`
- `.app__sidebar` — expanded nav, `var(--sidebar-w)`, `surface-nav`
- `.app__canvas` — main content area, `surface-page`, flex 1
- `.app__right-panel` — contextual right panel, `surface-nav`
- `.app__statusbar` — fixed bottom bar

Layout primitives (Every Layout inspired):
- `.l-stack` / `.l-stack--{xs|sm|md|lg|xl}` — vertical rhythm
- `.l-cluster` / `.l-cluster--{start|end|between}` — horizontal flex
- `.l-grid` / `.l-grid--{2col|3col|4col}` — auto-fit grid
- `.l-sidebar` — sidebar + main, flex primitive
- `.l-center` — single-element centering
- `.l-spacer` — flex pushes elements apart

### Layer 4 — components.css

Every UI component. BEM naming. All visual styling lives here.

**BEM structure:**

```css
.block { }
.block__element { }
.block--modifier { }
.block__element--modifier { }

/* State classes */
.tab.is-active { }
.nav-item.is-active { }
.input.has-error { }
```

**BEM maps 1:1 to React:**
- `.btn--primary` → `<Button variant="primary">`
- `.badge--champion` → `<Badge state="champion">`
- `.input--error` → `<Input error>`
- `.nav-item.is-active` → `<NavItem active>`

**Selector rules:**
- Allowed: single class, class + modifier, class + state, class + pseudo, class + direct child
- Forbidden: ID selectors, tag selectors in components.css, descendant depth > 2, `!important` outside layer 5, inline `style=` except true one-offs

**Specificity ceiling:** `0,1,0` for 95% of selectors. `0,2,0` acceptable for component + modifier. Higher = architecture violation.

### Layer 5 — utilities.css

Single-purpose escape hatches. Every rule carries `!important`. Use sparingly — if you reach for the same utility combination three or more times, make it a component.

```css
.u-hidden        { display: none !important; }
.u-sr-only       { /* screen-reader only pattern */ }
.u-truncate      { overflow: hidden; text-overflow: ellipsis; white-space: nowrap; }
.u-text-center   { text-align: center !important; }
.u-fw-medium     { font-weight: var(--fw-medium) !important; }
.u-mono          { font-family: var(--font-mono) !important; }
.u-flex-1        { flex: 1 1 0% !important; }
.u-ml-auto       { margin-left: auto !important; }
```

---

## 3. Color palette

Full token set. See `verity-design-sample.html` for rendered swatches.

### Surfaces

| Token | Light | Dark | Usage |
|---|---|---|---|
| `--surface-page` | `#FAFBFC` | `#1A1D23` | Page background — main canvas |
| `--surface-panel` | `#FFFFFF` | `#22262F` | Cards, elevated content |
| `--surface-nav` | `#EBEDF2` | `#13151A` | Topbar, sidebar, left rail |
| `--surface-recessed` | `#F3F4F6` | `#161920` | Input backgrounds, recessed areas |
| `--surface-hover` | `#E9EBF0` | `#2A2F3A` | Hover states |

### Text

| Token | Light | Dark | Usage |
|---|---|---|---|
| `--text-primary` | `#111827` | `#E8EBF0` | Body copy, headings |
| `--text-secondary` | `#374151` | `#9BA3B8` | Labels, secondary content |
| `--text-tertiary` | `#6B7280` | `#636B80` | Hints, placeholders, captions |
| `--text-disabled` | `#9CA3AF` | `#434A5C` | Disabled states |

### Borders

| Token | Light | Dark | Usage |
|---|---|---|---|
| `--border-default` | `#DDE1E7` | `#343B4A` | Default borders |
| `--border-faint` | `rgba(0,0,0,0.05)` | `rgba(255,255,255,0.05)` | Hairline dividers |
| `--border-strong` | `#C2C8D4` | `#4A5266` | Emphasis borders |

### Slate blue — brand and interactive

| Token | Light | Dark | Usage |
|---|---|---|---|
| `--color-brand` | `#2C4E7E` | `#7AA3D4` | Buttons, links, active states |
| `--color-brand-hover` | `#3B6091` | `#8FB5E0` | Hover on brand elements |
| `--color-brand-faint` | `#EEF4FA` | `rgba(122,163,212,0.10)` | Active nav bg, badge bg |
| `--color-brand-wash` | `#E0EAF4` | `rgba(122,163,212,0.16)` | Info callout bg |
| `--color-brand-border` | `#C5D5E8` | `rgba(122,163,212,0.30)` | Info callout border |

### Muted green — positive / champion / success

| Token | Light | Dark |
|---|---|---|
| `--color-positive` | `#2D6A4F` | `#5DA882` |
| `--color-positive-bg` | `#EDF7F3` | `rgba(93,168,130,0.10)` |
| `--color-positive-wash` | `#DCF0E8` | `rgba(93,168,130,0.16)` |
| `--color-positive-border` | `#C4DDD3` | `rgba(93,168,130,0.30)` |

### Muted red — negative / deprecated / error

| Token | Light | Dark |
|---|---|---|
| `--color-negative` | `#7A2233` | `#C47A88` |
| `--color-negative-bg` | `#F8ECEE` | `rgba(196,122,136,0.10)` |
| `--color-negative-wash` | `#F0D8DC` | `rgba(196,122,136,0.16)` |
| `--color-negative-border` | `#DFC0C7` | `rgba(196,122,136,0.30)` |

### Muted amber — warning / challenger

| Token | Light | Dark |
|---|---|---|
| `--color-warning` | `#7A5020` | `#C4A06A` |
| `--color-warning-bg` | `#F7EFE0` | `rgba(196,160,106,0.10)` |
| `--color-warning-wash` | `#EFE0C4` | `rgba(196,160,106,0.16)` |
| `--color-warning-border` | `#DECCAE` | `rgba(196,160,106,0.30)` |

### Dark mode

Apply `.dark` to `<body>` or `<html>`. All semantic tokens remap — component CSS is untouched.

```css
.dark {
  --surface-page:    #1A1D23;
  --surface-panel:   #22262F;
  --surface-nav:     #13151A;
  /* ... all tokens remapped */
}
```

The surface hierarchy in dark mode must produce three visible depth layers: nav (`#13151A`) → canvas (`#1A1D23`) → card (`#22262F`). If the nav and canvas are indistinguishable, the hierarchy is broken.

---

## 4. Typography

**Fonts:** IBM Plex Sans (UI chrome) + IBM Plex Mono (prompt content, UUIDs, decision log output, code). Loaded from Google Fonts.

```css
--font-ui:   "IBM Plex Sans", system-ui, sans-serif;
--font-mono: "IBM Plex Mono", "Cascadia Code", "Consolas", monospace;
```

**Why IBM Plex:** humanist sans, precise and professional without coldness. The mono variant is essential — Verity surfaces structured AI output, UUIDs, SQL, and prompt content constantly. A matched mono/sans pair removes the jarring weight-mismatch common with mixed font families.

**Type scale:**

| Token | Size | Weight | Usage |
|---|---|---|---|
| `--fs-hero` | 28px | 600 | Page titles |
| `--fs-title` | 20px | 600 | Section headings |
| `--fs-h3` | 15px | 600 | Card headings, panel titles |
| `--fs-body` | 14px | 400 | Body copy, form labels |
| `--fs-label` | 13px | 500 | UI labels, nav items |
| `--fs-caption` | 11px | 400 | Timestamps, secondary meta |
| `--fs-eyebrow` | 10px | 600 | Section labels (uppercase, tracked) |
| `--fs-mono` | 12px | 400 | Monospace content |

**Eyebrow pattern** — used for all section labels, column headers, and category labels:

```css
font-size: 10px;
font-weight: 600;
letter-spacing: 0.08em;
text-transform: uppercase;
color: var(--text-tertiary);
```

---

## 5. Spacing and radius

**Spacing scale** (4px base):

```css
--space-1: 4px;   --space-2: 8px;   --space-3: 12px;  --space-4: 16px;
--space-5: 20px;  --space-6: 24px;  --space-7: 32px;  --space-8: 40px;
--space-9: 48px;
```

**Radius scale:**

```css
--radius-xs:   2px;    /* tight internal elements */
--radius-sm:   4px;    /* badges, chips, inputs */
--radius-md:   6px;    /* buttons, small cards */
--radius-lg:   8px;    /* cards, panels */
--radius-xl:   12px;   /* large containers, modals */
--radius-pill: 999px;  /* deliberate pill shapes only */
```

Badges and state chips use `--radius-sm` (4px) — rounded rectangle, not pill. Pills are reserved for toggles and explicitly rounded affordances.

---

## 6. Components

### Buttons

Four variants, three sizes. All dark-background, white-text — no light tinted button backgrounds.

```css
/* Primary — slate blue */
.btn--primary { background: var(--color-brand); color: #FFFFFF; }

/* Secondary / ghost — dark charcoal */
.btn--secondary { background: #1F2937; color: #FFFFFF; border: 1px solid #374151; }

/* Positive — dark green */
.btn--positive { background: #2D6A4F; color: #FFFFFF; }

/* Danger — dark red */
.btn--danger { background: #7A2233; color: #FFFFFF; }
```

Sizes: `--sm` (5px 10px, 12px), `--md` (7px 14px, 13px — default), `--lg` (9px 18px, 14px).

Disabled: `opacity: 0.38; cursor: not-allowed` on any variant.

### Badges (lifecycle state)

Rounded rectangle (4px radius), uppercase, 10px/600 weight, 0.07em letter-spacing. Each state has a dot indicator.

| State | Background | Text | Border | Dot |
|---|---|---|---|---|
| `draft` | `--surface-panel` | `--text-tertiary` | `--border-default` | `--text-disabled` |
| `candidate` | `--color-brand-faint` | `--color-brand` | `--color-brand-border` | `--color-brand` |
| `staging` | `--color-brand-wash` | `--c-blue-900` | `--color-brand-border` | `--c-blue-700` |
| `shadow` | `--surface-recessed` | `--text-secondary` | `--border-default` | `--text-tertiary` |
| `challenger` | `--color-warning-bg` | `--color-warning` | `--color-warning-border` | `--color-warning` |
| `champion` | `--color-positive-bg` | `--color-positive` | `--color-positive-border` | `--color-positive` |
| `deprecated` | `#EAECF0` | `#4B5563` | `#D1D5DB` | `#9CA3AF` |

Deprecated uses hardcoded values — it must not share the red negative palette. Dark gray reads as "retired" rather than "error."

Materiality tier badges follow the same shape:
- `high` → negative palette
- `medium` → warning palette
- `low` → neutral gray

### Callouts

Left-border accent, matching background wash. No rounded corners on the left side.

```css
.callout { border-left: 3px solid; border-radius: 0 var(--radius-md) var(--radius-md) 0; padding: 10px 14px; }
.callout--info    { border-color: var(--color-brand);    background: var(--color-brand-wash); }
.callout--success { border-color: var(--color-positive); background: var(--color-positive-wash); }
.callout--warning { border-color: var(--color-warning);  background: var(--color-warning-wash); }
.callout--error   { border-color: var(--color-negative); background: var(--color-negative-wash); }
```

### Cards

White background (`--surface-panel`), 0.5px border, `--radius-lg`, `--shadow-sm`. Hover lifts to `--shadow-md` and tightens border.

```css
.card { background: var(--surface-panel); border: 0.5px solid var(--border-default); border-radius: var(--radius-lg); box-shadow: var(--shadow-sm); }
.card:hover { box-shadow: var(--shadow-md); border-color: var(--border-strong); }
```

### Inputs

```css
.input { background: var(--surface-panel); border: 1px solid var(--border-default); border-radius: var(--radius-md); padding: 8px 12px; font-size: 13px; }
.input:focus { border-color: var(--color-brand); box-shadow: var(--ring-focus); }
.input--mono { font-family: var(--font-mono); font-size: 12px; }
.input--error { border-color: var(--color-negative-border); background: var(--color-negative-bg); }
```

Focus ring: `box-shadow: 0 0 0 3px rgba(44,78,126,0.22)` in light mode, `rgba(122,163,212,0.28)` in dark.

### Tables (decision log, entity lists)

Borderless rows with `--border-faint` dividers. Column headers use the eyebrow pattern. Alternate rows use `--surface-recessed` fill when table is long.

```css
.log-table { border: 0.5px solid var(--border-default); border-radius: var(--radius-lg); overflow: hidden; }
.log-table__header { background: var(--surface-recessed); /* eyebrow typography */ }
.log-row { border-bottom: 0.5px solid var(--border-faint); transition: background var(--dur-fast); }
.log-row:hover { background: var(--surface-recessed); }
```

---

## 7. Navigation — apps-based model

Verity uses an **apps-based navigation model**, not a monolithic nav tree. Each major capability (Intake, Studio, Registry, Runs, Compliance, Settings) is an independent app. Users pin apps, access recent apps, and search via a command palette.

> **Reference implementation:** `specs/ui/verity-nav-framework.html` — the canonical illustration of the apps-based model (left rail, sidebar, topbar, app launcher, command palette).

### Left rail

The leftmost column (48px wide). Contains:
- Wordmark / logo mark at top
- Pinned app icons (icon only, tooltip on hover)
- Spacer
- Recent app icons (slightly muted)
- Grid icon at bottom → opens app launcher modal

```css
.app__left-rail { width: 48px; background: var(--surface-nav); border-right: 0.5px solid var(--border-default); }
.rail-app-icon { /* 36px × 36px, --radius-md, centered icon */ }
.rail-app-icon.is-active { background: var(--color-brand-faint); color: var(--color-brand); }
```

### Sidebar

Expanded navigation within a selected app (200px wide, collapsible). Contains section labels (eyebrow) and nav items with icons.

```css
.sidebar { width: 200px; background: var(--surface-nav); border-right: 0.5px solid var(--border-default); }
.nav-item.is-active { background: var(--color-brand-faint); color: var(--color-brand); border-right: 2px solid var(--color-brand); }
```

### Topbar

44px, `--surface-nav`, always visible. Contains: wordmark, app nav tabs, spacer, actions, avatar.

```css
.topbar { height: 44px; background: var(--surface-nav); border-bottom: 0.5px solid var(--border-default); }
```

### App launcher modal

Full-screen overlay. Search box at top, grid of app tiles below. Apps show name, icon, one-line description. Pin control on hover.

Trigger: grid icon in left rail, or `Ctrl+J` / `Cmd+J`.

### Command palette

`Ctrl+J` / `Cmd+J` opens a search-first modal. Searches: app names, entity names (agents, tasks, prompts by name), recent runs by ID, settings. Results grouped by type. Keyboard navigable.

---

## 8. Getting-started and self-documenting pages

Every app has a defined empty state — not a blank screen.

**Empty state anatomy:**
```
[Icon — 32px, --text-tertiary]
[Title — "You haven't created any agents yet"]
[Body — one sentence explaining what agents are and why]
[Primary CTA button]
[Optional: "Learn more" → inline explainer, no modal]
```

**Contextual help:** every field label and action button has an adjacent `?` icon that opens an inline popover with:
- 2–3 sentence explanation
- A concrete example value
- A link to the relevant docs section (no dead links)

**Field-level error messages:** always below the field, never in a toast. Include what went wrong and what to do (`"Version 2.1.0 already exists for this agent — use 2.2.0 or later"`).

**Progress feedback:** any action that takes > 300ms shows a loading indicator. Any action that takes > 2s shows estimated progress.

---

## 9. Prompt editor architecture

The prompt editor is a **structured block editor** — not a raw textarea. Prompts are composed as an ordered array of typed blocks. Each block carries a content hash for blame computation.

### Block types

| Kind | Purpose | Key fields |
|---|---|---|
| `prose` | Plain instructional text | `text: string` |
| `var` | Runtime placeholder | `name`, `type`, `desc`, `eg`, `opts?`, `req` |
| `list` | Numbered instruction list | `items: string[]` |
| `table` | Reference table | `headers: string[]`, `rows: string[][]`, `caption?` |
| `code` | Syntax-highlighted example | `lang`, `code: string`, `caption?` |

Variable types: `string | number | code | enum | boolean`

Variable chips render inline as `{variable_name}` — amber-tinted, clickable to open popover. They are atomic nodes (cursor cannot enter), draggable, and carry governance metadata (type, description, example, required flag).

### Compiled output

On compile, the block array renders to a flat string:

```
prose  → plain text
var    → {variable_name} placeholder
list   → numbered lines (1. item\n2. item)
table  → GitHub-flavoured markdown table
code   → fenced code block (```lang\n...\n```)
```

Blocks joined with `\n\n`. Compile also computes and displays the SHA-256 of the compiled string — this becomes `content_sha256` stored on the prompt version row.

### Blame model

Blame is **computed, not stored**. Each block has a `content_hash` (SHA-256 of the block's JSON). On load, the system walks version history backwards for each block. The version where the block's hash last changed is the blame version for that block.

Consequence:
- A block untouched for 10 versions blames its original author
- Renaming a variable resets blame (new hash)
- Reordering blocks without editing content does not change blame

Blame surfaces in the gutter bar alongside each block. Click the gutter to see author, version SHA, age, and commit message. The gutter color encodes which author touched each block.

### Editor layout

```
┌─ left rail (block navigator + version list + blame key)
│   200px
├─ editor canvas (scrollable)
│   Flex 1
│   ├─ for each block:
│   │   ├─ GutterBar (colored blame bar, line numbers, click for tooltip)
│   │   └─ Block renderer (prose | var | list | table | code)
│   └─ InsertZone between every block (hover to reveal ⊕)
└─ right panel (variable index + blame log)
    200px
```

### Diff view

The diff view compares two prompt versions side-by-side in the same editor layout. Each block shows its change status:

- **Unchanged:** normal rendering, gutter shows original blame
- **Modified:** highlighted block (amber outline), expanded inline diff showing deleted lines (red wash, strikethrough) and added lines (green wash)
- **Added:** green wash background, `+` gutter marker
- **Removed:** red wash background, `−` gutter marker, grayed out

The diff is computed client-side using `diff-match-patch` against the `content` fields of two `prompt_version` rows. No server round-trip required.

**Diff toolbar** shows: version labels, change summary text, `+N / −N` line counts, net token delta, and number of test failures attributable to changed blocks.

**Block-level failure attribution:** if a block's content hash changed between the current version and the last champion, and failing test cases have their blame pointing at that block, the diff view shows a failure count badge on that block. This connects the prompt diff directly to the test suite without requiring the author to cross-reference manually.

### Database schema

```sql
CREATE TABLE prompt_templates (
  id                 uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  name               text NOT NULL,
  description        text,
  current_version_id uuid,
  created_by         uuid NOT NULL,
  created_at         timestamptz NOT NULL DEFAULT now(),
  updated_at         timestamptz NOT NULL DEFAULT now()
);

-- Append-only. Never mutated.
CREATE TABLE prompt_template_versions (
  id                uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  template_id       uuid NOT NULL REFERENCES prompt_templates(id),
  version_number    integer NOT NULL,
  document          jsonb NOT NULL,        -- full block array
  content_sha256    text NOT NULL,         -- SHA-256 of compiled output
  commit_msg        text NOT NULL,
  authored_by       uuid NOT NULL,
  authored_at       timestamptz NOT NULL DEFAULT now(),
  parent_version_id uuid REFERENCES prompt_template_versions(id),
  UNIQUE (template_id, version_number)
);

-- Materialised index — rebuilt on each save, enables cross-version queries
CREATE TABLE prompt_template_nodes (
  id           uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  template_id  uuid NOT NULL,
  version_id   uuid NOT NULL,
  node_id      text NOT NULL,
  kind         text NOT NULL,
  position     integer NOT NULL,
  var_name     text,
  var_type     text,
  var_required boolean,
  content_hash text NOT NULL,   -- SHA-256(JSON.stringify(block))
  UNIQUE (version_id, node_id)
);
```

**Save flow (one transaction):**
1. Increment `version_number` for this template
2. `INSERT prompt_template_versions` — full document JSONB + `content_sha256` + commit message
3. `INSERT prompt_template_nodes` — one row per block with `content_hash`
4. `UPDATE prompt_templates SET current_version_id = new version id`

**Blame SQL (recursive CTE):**

```sql
WITH RECURSIVE chain AS (
  SELECT id, version_number, authored_by, authored_at, commit_msg, parent_version_id
  FROM prompt_template_versions
  WHERE id = :current_version_id
  UNION ALL
  SELECT v.id, v.version_number, v.authored_by, v.authored_at, v.commit_msg, v.parent_version_id
  FROM prompt_template_versions v
  JOIN chain c ON v.id = c.parent_version_id
)
SELECT chain.*, u.display_name AS author_name
FROM chain JOIN users u ON chain.authored_by = u.id
ORDER BY version_number ASC;
```

For each block in the current version, walk the chain backwards and find the version where `content_hash` differs from the previous version. Cache result in Redis keyed by `version_id`, 5-minute TTL.

### Production implementation

The prototype uses `useState<Block[]>`. Production target:

| Concern | Prototype | Production |
|---|---|---|
| Document model | `useState<Block[]>` | ProseMirror schema via TipTap v2 |
| Variable blocks | React state | TipTap `InlineNode` atom (cursor cannot enter) |
| Code blocks | Textarea | TipTap node + embedded CodeMirror 6 |
| Undo/redo | Not implemented | ProseMirror history extension |
| Collaboration | Not implemented | Y.js + TipTap collab extension |

**Variable node in TipTap:**

```typescript
const PromptVariable = Node.create({
  name: 'promptVariable',
  group: 'inline',
  inline: true,
  atom: true,      // cursor cannot enter
  draggable: true,
  addAttributes() {
    return {
      name: { default: '' },
      type: { default: 'string' },
      required: { default: true },
      desc: { default: '' },
      example: { default: '' },
      options: { default: [] },
    }
  },
  addNodeView() {
    return ReactNodeViewRenderer(VarChipNodeView)
  }
})
```

---

## 10. Authoring canvas architecture

The canvas is the **agent or task** — not the prompt. The prompt is one wired component inside the entity. This is the correct mental model and it determines the entire layout.

```
Old mental model: canvas = prompt text, everything else = settings panel
Correct model:    canvas = entity composition, prompt = one section of it
```

> **Reference implementation:** `specs/ui/verity-agent-studio.html` — the current, stronger
> agent-compose experience and the canonical reference for this section. The earlier
> `specs/ui/verity_authoring_canvas_model.html` is a superseded sketch.

### Canvas anatomy

```
┌─ left panel (library — 200px)
│   Available prompts (filtered to compatible versions)
│   Available tools (drag to wire)
│   Inference configs (select to apply)
│   Data connectors (for source bindings)
│   Delegate agents (for agent → agent delegation)
│
├─ centre canvas (entity composition — flex 1)
│   Breadcrumb: Studio / Agents / entity_name [lifecycle badge] [version badge]
│   │
│   ├─ INPUT BINDINGS section
│   │   One row per binding: source_field → {{template_var}} :: resolution_strategy
│   │   Binding kinds: input_data.field | fetch:connector.method | const:value
│   │   content_blocks bindings carry a special badge (PDF/vision inputs)
│   │
│   ├─ PROMPT section (for each prompt in entity_prompt_assignment)
│   │   Header: prompt name, version, [Open editor] button
│   │   Body: compiled prompt preview with variable chips inline
│   │   Footer: SHA-256 of compiled content, token count, governance tier
│   │
│   ├─ TOOLS section (agents only)
│   │   Chip grid of authorised tools + [Add tool] chip
│   │   Mock mode toggle (per-section, not global)
│   │
│   ├─ DELEGATION section (agents only)
│   │   Chip grid of authorised delegate agents with lifecycle badge
│   │
│   ├─ OUTPUT SCHEMA section
│   │   Field table: name : type : required : validation rule
│   │   For extraction tasks: field-level match config (exact | numeric tolerance | fuzzy)
│   │
│   ├─ WRITE TARGETS section (tasks)
│   │   One row per target: output.field_name → connector.write_method
│   │   Channel gate shown inline (champion only / log-only in staging)
│   │
│   └─ HOOKS section
│       post_extract / pre_write / on_low_confidence hooks with their conditions
│
└─ right panel (test + inspect — 190px)
    Test form: one input per input_data field
    File upload / vault reference pickers
    [Run] button
    Last output (monospace, collapsible)
    [Save to test suite] button
    Decision log link (run ID, duration, token count)
    Performance summary (pass rate, avg latency)
```

### Composition immutability rule

Once an entity version advances from `draft` to `candidate`:
- Prompt assignments lock
- Tool authorisations lock
- Inference config locks
- Input bindings lock
- Output schema locks

Any change requires cloning to a new version. The canvas makes this visually clear: draft versions show editable sections, candidate+ versions show read-only sections with a "Clone to edit" prompt.

### Section-level mock mode

Mock mode is configurable per section (per tool, per connector), not globally. This allows:
- Testing with live prompt resolution but mocked tool responses
- Testing with mocked connector fetches but live Claude calls
- Fully mocked runs for ground truth generation

### State machine for the canvas

```
Empty → entity created → Draft (editable canvas)
Draft → promote to Candidate → Candidate (canvas read-only, tests run)
Candidate → promote to Staging → Staging (test suite gated)
Staging → promote to Challenger → Challenger (prod evaluation; deploy in shadow OR ab run-mode, switchable)
Challenger → promote to Champion → Champion (live production)
Champion → deprecate → Deprecated (locked; restorable via rollback)
Rollback: Deprecated → Champion (restore a prior champion)
```

The lifecycle badge in the breadcrumb reflects the current state. All promotion actions require the approval gate (documented in `specs/schema/verity_schema.sql` on the `approval_record` table).

---

## 11. Diff architecture

The diff system surfaces at two levels: **prompt block diff** (within the prompt editor) and **composition diff** (within the authoring canvas, comparing entity versions).

### Diff computation

Both levels use the same client-side algorithm:

1. Fetch the two versions' full document JSON from the API
2. For each block in the newer version, find the corresponding block in the older version by `node_id`
3. If `content_hash` is identical → unchanged
4. If `content_hash` differs → compute line-level diff using `diff-match-patch` on the JSON-serialised content
5. If a block exists in old but not new → deleted
6. If a block exists in new but not old → added

The diff is never stored. It is always computed on demand from the two version rows.

### Diff display

**Unchanged blocks:** render normally. Gutter shows original blame.

**Modified blocks:**
```
Amber outline (2px) on the block container
Expanded inline diff replacing the normal block render:
  - Deleted lines: red wash bg + red text + line-through + "−" gutter marker
  - Added lines:   green wash bg + green text + "+" gutter marker
  - Context lines: normal rendering, muted
  - Inline character-level changes: --inline-del (red) and --inline-add (green)
```

**Added blocks:** green wash background, `+` in gutter, full content shown.

**Deleted blocks:** red wash background, `−` in gutter, full content shown with strikethrough.

### Blame attribution in diff

When a block is modified and failing test cases exist whose blame points at that block:
- A `badge--red` appears in the block header showing the failure count
- The blame tooltip shows which test cases are affected
- The right panel shows the total failure count across all modified blocks

This connects the diff view to the test suite without requiring a separate workflow.

### Diff toolbar

```
[version label A] [vs] [version label B] [change summary] [+N] [−N] [net token Δ] [test failures]
```

The toolbar is sticky at the top of the diff view. The focus banner below it highlights which block contains failures, allowing the reviewer to jump directly to the problem rather than reading the whole diff.

### Composition diff (entity level)

The authoring canvas compares two entity versions by diffing their composition:

- Prompt assignments: which prompt versions are wired (SHA comparison)
- Tool authorisations: which tools added or removed
- Input bindings: which bindings changed (source, template var, resolution strategy)
- Output schema: which fields added, removed, or changed type
- Inference config: which parameters changed

Composition diff is shown as a summary in the version history sidebar, not as an inline block diff. The full composition hash (SHA-256 of the canonical composition JSON) confirms whether two versions are behaviourally identical.

---

## 12. Test suite and performance view

### Saving to the test suite

When an author runs the entity in the right panel and approves the output:

1. Click "Save to test suite"
2. Prompt for: test case name, commit message, adversarial flag, metric type
3. The system captures:
   - `input_data` — exact inputs used in the run
   - `source_mocks` — connector responses at run time
   - `tool_mocks` — tool call responses at run time (for agents)
   - `expected_output` — the approved output (editable before saving)
   - `metric_type` — exact_match | field_accuracy | semantic_similarity | human_rubric
   - `is_adversarial` — flag for weighted regression testing

The saved record maps to `governance.test_case` in the schema. Source and tool mocks map to `governance.test_case_mock` with `mock_kind = 'source'` and `mock_kind = 'tool'` respectively.

### Performance view

Four stat tiles at the top of the panel: F1 score, pass rate, avg duration, avg cost.

Detailed breakdown:

| Metric | Source |
|---|---|
| F1 / precision / recall | `governance.validation_run` |
| Pass rate | `governance.test_execution_log` aggregated |
| Avg / P95 latency | `runtime.model_invocation_log` |
| Avg input / output tokens | `runtime.model_invocation_log` |
| Override rate | `runtime.hitl_override` |
| HITL rate | `runtime.agent_decision_log.hitl_required` |
| Avg cost | `analytics.v_model_invocation_cost` |

Failing cases show a "View failing cases" button that opens the test suite filtered to failures for this version. Each failing case shows: expected vs actual output, diff of the output fields, and the blame attribution linking the failure to the prompt block that changed.

---

## 13. Pragmatic triage view (nice to have)

> **Nice to have.** Not required for v1. Implement after core authoring canvas and test suite are stable.

The triage view surfaces the highest-priority actionable issues across all entities in the registry, without requiring the operator to navigate into each entity individually.

### What it surfaces

A single ranked list combining:

- **Test failures introduced in the last promotion** — which entities have new failures vs their previous version, ordered by failure count and materiality tier
- **HITL rate spikes** — entities whose human override rate in the last 7 days is more than 2× their 30-day baseline
- **Confidence drift** — entities whose average confidence score has dropped more than 0.05 vs the prior period
- **Challenger lagging** — challenger versions that have been running head-to-head for > 14 days without a promotion decision
- **Quota approaching** — applications within 20% of their monthly budget

### Triage row anatomy

Each item in the list shows:

```
[Entity name + version]  [Lifecycle badge]  [Triage signal]
[One-line description of the issue]
[Severity: high | medium | low]  [Age: "2 days"]  [Primary action button]
```

Primary action buttons:
- Test failure → "View failing cases"
- HITL spike → "View decision log"
- Confidence drift → "View performance"
- Challenger lagging → "Promote or retire"
- Quota approaching → "View quota"

### Implementation notes

The triage view is a read-only aggregation — no write operations. It reads from:
- `governance.test_execution_log` for failure counts per entity version
- `runtime.agent_decision_log` for HITL rate and confidence
- `governance.evaluation_run` for challenger age
- `governance.quota_check` for budget status

A daily materialized view (`analytics.triage_signals`) pre-computes the ranked list to avoid N+1 queries on page load. The view is refreshed on a cron every 15 minutes during business hours.

The triage view is not a dashboard — it has no charts, no sparklines, no KPI tiles. It is a prioritised action queue. The only goal is to surface what needs attention and provide a one-click path to the relevant detail view.

---

## 14. Motion and interaction

```css
--dur-fast: 120ms;
--dur-base: 180ms;
--ease-out: cubic-bezier(0.16, 1, 0.3, 1);
```

Transitions apply to: `background`, `color`, `border-color`, `box-shadow`. Never to `layout` properties (width, height, padding) — layout shifts are jarring in dense UI.

Hover states are instant (no transition). Focus states use the ring. Active/pressed states use `transform: scale(0.98)` on buttons.

`@media (prefers-reduced-motion: reduce)` disables all transitions and animations.

---

## 15. Responsive strategy

Desktop-first. The app is designed for ≥ 1280px viewports. Mobile is degraded-graceful, not designed.

| Breakpoint | Behaviour |
|---|---|
| ≥ 1280px | Full three-column canvas (left panel + canvas + right panel) |
| 900–1280px | Right panel collapses to drawer |
| < 900px | Left panel and right panel hidden; canvas full width |

The left rail is always visible (48px). The sidebar collapses to rail-only below 1280px. The topbar is always visible.

---

## 16. Accessibility

- Every interactive element is keyboard-navigable
- Focus ring visible on all focusable elements: `box-shadow: var(--ring-focus)`
- All icons that carry meaning have `aria-label` on the parent button; decorative icons have `aria-hidden="true"`
- All form fields have associated `<label>` elements (not just placeholder text)
- Color is never the only differentiator — state is also conveyed by icon, text, or shape
- Lifecycle badges include text labels, not dots only
- Minimum touch target: 36px × 36px
- `role="img"` with `<title>` and `<desc>` on all meaningful SVGs
- `.u-sr-only` for screen-reader-only content

---

## 17. File structure

```
verity-v2/
├── services/
│   └── verity-governance/
│       └── ui/
│           ├── src/
│           │   ├── styles/
│           │   │   ├── tokens.css        Layer 1
│           │   │   ├── base.css          Layer 2
│           │   │   ├── layout.css        Layer 3
│           │   │   ├── components.css    Layer 4
│           │   │   └── utilities.css     Layer 5
│           │   ├── components/           React components (BEM → JSX)
│           │   │   ├── Button/
│           │   │   ├── Badge/
│           │   │   ├── Card/
│           │   │   ├── PromptEditor/
│           │   │   ├── AuthoringCanvas/
│           │   │   ├── DiffViewer/
│           │   │   └── ...
│           │   ├── apps/                 Top-level app modules
│           │   │   ├── intake/
│           │   │   ├── studio/
│           │   │   ├── registry/
│           │   │   ├── runs/
│           │   │   └── compliance/
│           │   └── layouts/              App shell, nav components
│           └── public/
│               └── design-sample.html   Approved color + component reference
└── specs/
    └── ui/
        └── design-system.md             This document
```

---

## 18. Reference

**Approved color and component sample:** `public/design-sample.html` — open in browser to see all swatches, badges, buttons, cards, callouts, table, diff block, and app chrome in both light and dark mode.

**Prompt editor architecture:** Section 9 of this document + `prompt-editor-v2.jsx` (prototype implementation).

**Schema reference:** `specs/schema/verity_schema.sql` — all entity tables, governance tables, and runtime tables.

**PCR:** `specs/pcr/verity_v2_pcr.md` — architectural intent and open decisions.

**CLAUDE.md:** project root — standing instructions for Claude Code on every session.

**Canonical example files** (`specs/ui/`):

| File | Illustrates | Section |
|------|-------------|---------|
| `verity-design-sample.html` | Approved colors, components, app chrome (light + dark) | §3–§6 |
| `verity-nav-framework.html` | Apps-based navigation model | §7 |
| `verity-homepage.html` | Homepage / getting-started state | §8 |
| `verity-agent-studio.html` | **Agent/task compose** — current authoring-canvas reference | §10 |
| `prompt-editor-v2.jsx` | Prompt block editor prototype | §9 |
| `verity-intake-wireframe.html` | **Intake flow** — early-iteration UX; reference for the Intake feature spec | §7 (Intake app) |
| `verity_authoring_canvas_model.html` | Earlier authoring-canvas sketch (superseded by `verity-agent-studio.html`) | §10 |
| `triage_agent_failing_cases.html` | Pragmatic triage view | §13 |
