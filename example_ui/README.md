# Draftwright Wireframes — How to View

**Just double-click `index.html`.** No server, no setup.

Or open any single page directly from `pages/`.

---

## What's inside

```
wireframes/
├── index.html              ← hub: links to every wireframe page
├── README.md               ← you are here
├── styles/                 ← 5 CSS files, ITCSS-layered
│   ├── tokens.css            design tokens (CSS variables)
│   ├── base.css              reset + element baseline
│   ├── layout.css            app shell + layout primitives
│   ├── components.css        every UI component (BEM)
│   └── utilities.css         sparse helpers
├── shared.js               ← Lucide init + modal interactions
├── _partials/              ← reference snippets (not used by pages)
└── pages/                  ← 8 editor wireframes
    ├── editor-storm.html
    ├── editor-draft.html
    ├── editor-curate.html      ← canonical view (most components on display)
    ├── editor-polish.html
    ├── editor-proof.html
    ├── editor-publish.html
    ├── editor-focus.html
    └── editor-preview.html
```

---

## Notes for engineers

- **CSS is the deliverable.** The 5 stylesheets in `styles/` are copy-paste-ready for the React build. No transpilation needed.
- **BEM naming maps 1:1 to React component variants.** `.btn--primary` = `<Button variant="primary">`, `.missive--liked` = `<Missive liked>`, etc.
- **All design tokens live in `tokens.css`**. Component CSS only consumes semantic tokens (`var(--color-brand)`), never raw hex values.
- **Each page is self-contained.** No build step, no fetch calls, no JS dependency for layout. The only JS is `shared.js` which initialises Lucide icons and binds the keyboard-shortcuts modal.

---

## About `_partials/`

Earlier iteration used HTML partials loaded via `fetch()` for DRY chrome. That was reverted in favour of inlined static pages (no server requirement). The `_partials/*.html` files remain as **reference snippets** — open them to see chrome elements (topbar, status bar, panels) in isolation. They are not loaded by any page.

If chrome markup changes, update each page in `pages/` directly. There is no auto-propagation.

---

## Reference docs

- **Design system**: [`../design-system.md`](../design-system.md) — colours, typography, components, no-candy rules, the olive/terracotta dyad, diff treatment.
- **CSS architecture**: [`../css-architecture.md`](../css-architecture.md) — five-layer ITCSS structure, BEM naming, token tiering, anti-patterns.
- **Visual component preview**: [`../design-preview.html`](../design-preview.html) — every component on cream and dark surfaces.

---

## Browser support

Tested on current Chrome, Safari, Firefox. The design system uses CSS custom properties throughout — no IE11.

## Troubleshooting

**Icons show as broken boxes** — Lucide CDN failed to load. Check internet, or download Lucide locally.

**Fonts look like Times New Roman / Arial** — Google Fonts CDN failed. Same fix.

**Layout breaks below 900px width** — Expected. The app is desktop-first per the design system. Mobile is degraded-graceful, not designed.
