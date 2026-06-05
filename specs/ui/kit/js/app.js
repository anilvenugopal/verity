/* ============================================================================
   app.js — shared shell behaviour for the static kit pages.
   Plain ES, no framework. Authored so each piece maps to a future React hook/
   component. Loaded once per page; reads data-attributes, owns no app state.
   ============================================================================ */
(() => {
  'use strict';

  /* ── Icon sprite — inject once so <use href="#i-…"> resolves ────────────── */
  async function loadIcons() {
    const path = document.currentScript?.dataset.sprite
      || document.querySelector('[data-sprite-src]')?.getAttribute('data-sprite-src')
      || '../icons/sprite.svg';
    try {
      const svg = await (await fetch(path)).text();
      const holder = document.createElement('div');
      holder.hidden = true;
      holder.innerHTML = svg;
      document.body.prepend(holder);
    } catch (e) {
      console.warn('[kit] icon sprite failed to load from', path, '— serve over http (file:// blocks fetch).', e);
    }
  }

  /* ── Theme — toggle .dark on <body>, persist choice ─────────────────────── */
  const THEME_KEY = 'verity-theme';
  function applyTheme(t) {
    document.body.classList.toggle('dark', t === 'dark');
    document.querySelectorAll('[data-theme-label]').forEach((el) => { el.textContent = t === 'dark' ? 'Light' : 'Dark'; });
  }
  function initTheme() {
    let saved = null;
    try { saved = localStorage.getItem(THEME_KEY); } catch (e) {}
    applyTheme(saved || 'light');
    document.querySelectorAll('[data-theme-toggle]').forEach((btn) =>
      btn.addEventListener('click', () => {
        const next = document.body.classList.contains('dark') ? 'light' : 'dark';
        applyTheme(next);
        try { localStorage.setItem(THEME_KEY, next); } catch (e) {}
      })
    );
  }

  /* ── Overlays — generic open/close for launcher + palette ───────────────── */
  function openOverlay(el) {
    if (!el) return;
    el.hidden = false;
    const focusable = el.querySelector('input, button, [tabindex]');
    focusable?.focus();
  }
  function closeOverlay(el) { if (el) el.hidden = true; }
  function closeAllOverlays() { document.querySelectorAll('[data-overlay]').forEach(closeOverlay); }

  function initOverlays() {
    // open triggers
    document.querySelectorAll('[data-open]').forEach((trigger) =>
      trigger.addEventListener('click', () => openOverlay(document.getElementById(trigger.dataset.open)))
    );
    // close triggers (backdrop + ✕)
    document.querySelectorAll('[data-close]').forEach((el) =>
      el.addEventListener('click', (e) => { if (e.target === el || el.hasAttribute('data-close-btn')) closeOverlay(el.closest('[data-overlay]')); })
    );
    // keyboard: Cmd/Ctrl+J → command palette (design-system §7); Esc → close
    document.addEventListener('keydown', (e) => {
      if ((e.metaKey || e.ctrlKey) && e.key.toLowerCase() === 'j') {
        e.preventDefault();
        const palette = document.getElementById('palette');
        if (palette) { palette.hidden ? openOverlay(palette) : closeOverlay(palette); }
      } else if (e.key === 'Escape') {
        closeAllOverlays();
      }
    });
  }

  /* ── Command palette — filter result rows by query ──────────────────────── */
  function initPalette() {
    const input = document.querySelector('[data-palette-input]');
    if (!input) return;
    const rows = [...document.querySelectorAll('[data-palette-row]')];
    const empty = document.querySelector('[data-palette-empty]');
    input.addEventListener('input', () => {
      const q = input.value.trim().toLowerCase();
      let shown = 0;
      for (const r of rows) {
        const match = !q || r.dataset.paletteRow.toLowerCase().includes(q);
        r.hidden = !match;
        if (match) shown++;
      }
      // hide group headers with no visible rows
      document.querySelectorAll('[data-palette-group]').forEach((g) => {
        const any = [...g.querySelectorAll('[data-palette-row]')].some((r) => !r.hidden);
        g.hidden = !any;
      });
      if (empty) empty.hidden = shown > 0;
    });
  }

  /* ── boot ───────────────────────────────────────────────────────────────── */
  function boot() { loadIcons(); initTheme(); initOverlays(); initPalette(); }
  if (document.readyState === 'loading') document.addEventListener('DOMContentLoaded', boot);
  else boot();
})();
