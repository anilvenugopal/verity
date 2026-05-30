/* ═══════════════════════════════════════════════════════════════════
   DRAFTWRIGHT WIREFRAMES — shared.js
   Lucide icon init · modal interactions · mock data store

   Pages are fully inlined static HTML — no partial loader needed.
   This file is loaded once per page after the Lucide CDN.
   ═══════════════════════════════════════════════════════════════════ */

(function () {
  'use strict';

  /* ─────────────────────────────────────────────────────────────
     1. Mock data (available as window.DW for any custom page JS)
     ───────────────────────────────────────────────────────────── */

  const PHASES = [
    { id: 'storm',   label: 'Storm',   icon: 'wind',          desc: 'Ideation & angle exploration' },
    { id: 'draft',   label: 'Draft',   icon: 'pen-line',      desc: 'First full article assembly' },
    { id: 'curate',  label: 'Curate',  icon: 'filter',        desc: 'Accept, reject, reshape' },
    { id: 'polish',  label: 'Polish',  icon: 'sparkles',      desc: 'Voice & rhythm refinement' },
    { id: 'proof',   label: 'Proof',   icon: 'shield-check',  desc: 'Final checks & guardrails' },
    { id: 'publish', label: 'Publish', icon: 'send',          desc: 'Export & ship' }
  ];

  const SOURCES = {
    claude: { glyph: 'asterisk', label: 'Claude' },
    grok:   { glyph: 'x',        label: 'Grok' },
    author: { glyph: 'feather',  label: 'You' }
  };

  const REVIEWERS = [
    { id: 'sk', initials: 'SK', name: 'Sarah K.',  online: true },
    { id: 'tr', initials: 'TR', name: 'Tom R.',    online: true },
    { id: 'dm', initials: 'DM', name: 'Dana M.',   online: false }
  ];

  /* ─────────────────────────────────────────────────────────────
     2. Lucide init (idempotent, retries until CDN is loaded)
     ───────────────────────────────────────────────────────────── */

  function initLucide(retries) {
    retries = retries || 0;
    if (typeof lucide !== 'undefined' && lucide.createIcons) {
      lucide.createIcons();
    } else if (retries < 50) {
      setTimeout(function () { initLucide(retries + 1); }, 50);
    } else {
      console.warn('[shared.js] Lucide CDN failed to load. Icons will not render.');
    }
  }

  /* ─────────────────────────────────────────────────────────────
     3. Modal open/close (shortcuts overlay + any [data-modal])
     ───────────────────────────────────────────────────────────── */

  function bindModals() {
    document.addEventListener('click', function (e) {
      // Open
      var openBtn = e.target.closest('[data-action="open-shortcuts"]');
      if (openBtn) {
        var openEl = document.querySelector('[data-modal="shortcuts"]');
        if (openEl) openEl.removeAttribute('hidden');
        return;
      }
      // Close
      var closeBtn = e.target.closest('[data-action="close-shortcuts"]');
      if (closeBtn) {
        var closeEl = document.querySelector('[data-modal="shortcuts"]');
        if (closeEl) closeEl.setAttribute('hidden', '');
        return;
      }
      // Click overlay to dismiss
      if (e.target.matches('[data-modal]')) {
        e.target.setAttribute('hidden', '');
      }
    });

    document.addEventListener('keydown', function (e) {
      if (e.target.tagName === 'INPUT' || e.target.tagName === 'TEXTAREA') return;
      var modal = document.querySelector('[data-modal="shortcuts"]');
      if (!modal) return;
      if (e.key === 'Escape') modal.setAttribute('hidden', '');
      if (e.key === '?')      modal.toggleAttribute('hidden');
    });
  }

  /* ─────────────────────────────────────────────────────────────
     4. Public API
     ───────────────────────────────────────────────────────────── */

  window.DW = { PHASES, SOURCES, REVIEWERS, reload: initLucide };

  /* ─────────────────────────────────────────────────────────────
     5. Boot
     ───────────────────────────────────────────────────────────── */

  function boot() {
    bindModals();
    initLucide();
  }

  if (document.readyState === 'loading') {
    document.addEventListener('DOMContentLoaded', boot);
  } else {
    boot();
  }
})();
