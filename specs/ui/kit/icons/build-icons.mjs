#!/usr/bin/env node
// Build the Verity icon sprite + interactive review catalog from icons.json.
//
//   node build-icons.mjs
//
// Outputs (regenerable — do not hand-edit):
//   sprite.svg    — <symbol id="i-<id>"> per semantic id (chosen glyph), for production
//   catalog.html  — self-contained review tool: alternatives, live conflict flags,
//                   per-icon approve/change/review + notes, and a JSON export of decisions
//
// Source of truth is icons.json. To add/swap/approve an icon, edit the manifest and re-run.

import { readFile, writeFile } from 'node:fs/promises'
import { fileURLToPath } from 'node:url'
import { dirname, join } from 'node:path'

const HERE = dirname(fileURLToPath(import.meta.url))
const manifest = JSON.parse(await readFile(join(HERE, 'icons.json'), 'utf8'))
const { iconSetVersion } = manifest.meta
const CDN = (name) => `https://cdn.jsdelivr.net/npm/lucide-static@${iconSetVersion}/icons/${name}.svg`

const allIcons = manifest.categories.flatMap((c) => c.icons)

// ---- collect every glyph we need (primaries + alternatives) -------------
const wanted = new Set()
for (const i of allIcons) {
  wanted.add(i.lucide)
  for (const a of i.alt || []) wanted.add(a)
}
const wantedList = [...wanted]
process.stdout.write(`Fetching ${wantedList.length} Lucide glyphs (v${iconSetVersion})…\n`)

const inner = {}
const missing = []
await Promise.all(
  wantedList.map(async (name) => {
    const res = await fetch(CDN(name))
    if (!res.ok) { missing.push(name); return }
    const svg = await res.text()
    inner[name] = svg.replace(/^[\s\S]*?<svg[^>]*>/, '').replace(/<\/svg>\s*$/, '').trim()
  })
)
if (missing.length) process.stdout.write(`  ⚠ ${missing.length} not in Lucide, dropped: ${missing.join(', ')}\n`)

// resolved option list per icon (primary first, only glyphs that exist)
const opts = (i) => [i.lucide, ...(i.alt || [])].filter((n) => inner[n])
for (const i of allIcons) {
  if (!inner[i.lucide]) process.stdout.write(`  ⚠ PRIMARY missing for ${i.id}: ${i.lucide}\n`)
}

// ---- glyph symbols (one per resolved lucide name) -----------------------
const SYM =
  'viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" ' +
  'stroke-linecap="round" stroke-linejoin="round"'
const glyphSymbols = wantedList
  .filter((n) => inner[n])
  .map((n) => `  <symbol id="g-${n}" ${SYM}>${inner[n]}</symbol>`)
  .join('\n')
const glyphSprite =
  `<svg xmlns="http://www.w3.org/2000/svg" style="display:none" aria-hidden="true" data-glyphs>\n${glyphSymbols}\n</svg>\n`

// ---- production sprite (semantic ids → chosen glyph) --------------------
const prodSprite =
  `<svg xmlns="http://www.w3.org/2000/svg" style="display:none" aria-hidden="true">\n` +
  `<!-- Verity icon sprite — generated from icons.json by build-icons.mjs. Do not edit. -->\n` +
  `<!-- Lucide v${iconSetVersion} (ISC). ${allIcons.length} symbols. -->\n` +
  allIcons.map((i) => `  <symbol id="i-${i.id}" ${SYM}>${inner[i.lucide] || ''}</symbol>`).join('\n') +
  `\n</svg>\n`
await writeFile(join(HERE, 'sprite.svg'), prodSprite)
process.stdout.write(`Wrote sprite.svg (${allIcons.length} symbols)\n`)

// ---- conflict report (primaries reused across ids) ----------------------
const byGlyph = {}
for (const i of allIcons) (byGlyph[i.lucide] ??= []).push(i.id)
const conflicts = Object.entries(byGlyph).filter(([, ids]) => ids.length > 1)
if (conflicts.length)
  process.stdout.write(
    `  ⓘ ${conflicts.length} glyph(s) reused (flagged in catalog): ` +
    conflicts.map(([g, ids]) => `${g}→{${ids.join(',')}}`).join('  ') + '\n'
  )

// ---- catalog page -------------------------------------------------------
const esc = (s) => String(s).replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;')
const attr = (s) => esc(s).replace(/"/g, '&quot;')

const optionBtn = (lucide, isPrimary) =>
  `<button class="opt${isPrimary ? ' is-primary' : ''}" type="button" data-lucide="${attr(lucide)}" title="${attr(lucide)}${isPrimary ? '  (current)' : ''}">` +
  `<svg class="icon" aria-hidden="true"><use href="#g-${attr(lucide)}"></use></svg></button>`

const card = (i) => {
  const options = opts(i)
  const search = (i.id + ' ' + i.label + ' ' + options.join(' ') + ' ' + i.usage).toLowerCase()
  return `
        <div class="card" data-id="${attr(i.id)}" data-primary="${attr(i.lucide)}" data-search="${attr(search)}">
          <div class="card__top">
            <span class="card__glyph"><svg class="icon icon--lg" aria-hidden="true"><use href="#g-${attr(i.lucide)}" data-chosen-use></use></svg></span>
            <span class="card__meta">
              <span class="card__label">${esc(i.label)}</span>
              <span class="card__id">i-${esc(i.id)}</span>
              <span class="card__lucide" data-chosen-name>${esc(i.lucide)}</span>
            </span>
            <span class="card__conflict" data-conflict hidden>reused</span>
          </div>
          <p class="card__usage">${esc(i.usage)}</p>
          <div class="card__opts" role="group" aria-label="Glyph options for ${attr(i.label)}">
            ${options.map((o, n) => optionBtn(o, n === 0)).join('')}
          </div>
          <div class="card__review">
            <div class="status" role="group" aria-label="Decision">
              <button class="status__btn" data-status="approved" type="button">Approve</button>
              <button class="status__btn" data-status="change"   type="button">Change</button>
              <button class="status__btn" data-status="review"   type="button">Review</button>
            </div>
            <input class="note" type="text" placeholder="note…" aria-label="Note for ${attr(i.label)}">
          </div>
        </div>`
}

const sectionEl = (c) => `
      <section class="cat" data-cat data-cat-id="${attr(c.id)}">
        <div class="cat__head">
          <h2 class="cat__title">${esc(c.label)}</h2>
          <span class="cat__ref">${esc(c.ref || '')}</span>
          <span class="cat__count">${c.icons.length}</span>
        </div>
        <div class="cat__grid">${c.icons.map(card).join('')}</div>
      </section>`

const page = `<!DOCTYPE html>
<html lang="en">
<head>
<meta charset="UTF-8">
<meta name="viewport" content="width=device-width, initial-scale=1.0">
<title>${esc(manifest.meta.name)} — Review</title>
<link href="https://fonts.googleapis.com/css2?family=IBM+Plex+Mono:wght@400;500&family=IBM+Plex+Sans:wght@300;400;500;600&display=swap" rel="stylesheet">
<style>
/* NOTE: interim inlined tokens copied from verity-design-sample.html.
   Replace with a <link> to the shared tokens.css once it is extracted. */
:root{
  --c-blue-900:#1D3557; --c-blue-700:#2C4E7E; --c-blue-600:#3B6091; --c-blue-050:#EEF4FA;
  --surface-page:#FAFBFC; --surface-panel:#FFFFFF; --surface-nav:#EBEDF2; --surface-recessed:#F3F4F6;
  --text-primary:#111827; --text-secondary:#374151; --text-tertiary:#6B7280; --text-disabled:#9CA3AF;
  --border-default:#DDE1E7; --border-strong:#C2C8D4;
  --color-brand:#2C4E7E; --color-brand-hover:#3B6091; --color-brand-faint:#EEF4FA; --color-brand-border:#C5D5E8;
  --color-positive:#2D6A4F; --color-positive-bg:#EDF7F3; --color-positive-border:#C4DDD3;
  --color-warning:#7A5020; --color-warning-bg:#F7EFE0; --color-warning-border:#DECCAE;
  --color-negative:#7A2233; --color-negative-bg:#F8ECEE; --color-negative-border:#DFC0C7;
  --font-ui:"IBM Plex Sans",system-ui,sans-serif; --font-mono:"IBM Plex Mono","Cascadia Code","Consolas",monospace;
  --space-2:8px; --space-3:12px; --space-4:16px; --space-6:24px; --space-7:32px;
  --radius-sm:4px; --radius-md:6px; --radius-lg:8px;
  --ring-focus:0 0 0 3px rgba(44,78,126,.22);
  --shadow-sm:0 1px 2px rgba(16,24,40,.04),0 1px 3px rgba(16,24,40,.06);
  --shadow-md:0 2px 4px rgba(16,24,40,.06),0 4px 8px rgba(16,24,40,.08);
}
body.dark{
  --surface-page:#1A1D23; --surface-panel:#22262F; --surface-nav:#13151A; --surface-recessed:#161920;
  --text-primary:#E8EBF0; --text-secondary:#9BA3B8; --text-tertiary:#636B80; --text-disabled:#434A5C;
  --border-default:#343B4A; --border-strong:#4A5266;
  --color-brand:#7AA3D4; --color-brand-hover:#8FB5E0; --color-brand-faint:rgba(122,163,212,.10); --color-brand-border:rgba(122,163,212,.30);
  --color-positive:#5DA882; --color-positive-bg:rgba(93,168,130,.10); --color-positive-border:rgba(93,168,130,.30);
  --color-warning:#C4A06A; --color-warning-bg:rgba(196,160,106,.10); --color-warning-border:rgba(196,160,106,.30);
  --color-negative:#C47A88; --color-negative-bg:rgba(196,122,136,.10); --color-negative-border:rgba(196,122,136,.30);
  --ring-focus:0 0 0 3px rgba(122,163,212,.28);
}
*{box-sizing:border-box}
body{margin:0;font-family:var(--font-ui);font-size:14px;color:var(--text-primary);background:var(--surface-page);-webkit-font-smoothing:antialiased}
.icon{width:20px;height:20px;display:block;color:currentColor}
.icon--lg{width:26px;height:26px}
.topbar{position:sticky;top:0;z-index:20;display:flex;align-items:center;gap:var(--space-4);height:56px;padding:0 var(--space-6);
  background:var(--surface-nav);border-bottom:.5px solid var(--border-default)}
.topbar__title{font-size:15px;font-weight:600;letter-spacing:-.01em}
.topbar__meta{font-size:11px;color:var(--text-tertiary);font-family:var(--font-mono)}
.spacer{flex:1}
.search{display:flex;align-items:center;gap:var(--space-2);background:var(--surface-recessed);border:1px solid var(--border-default);
  border-radius:var(--radius-md);padding:7px 12px;width:240px}
.search:focus-within{border-color:var(--color-brand);box-shadow:var(--ring-focus)}
.search input{border:0;outline:0;background:transparent;font:inherit;color:inherit;width:100%}
.search .icon{width:16px;height:16px;color:var(--text-tertiary)}
.btn{display:inline-flex;align-items:center;gap:6px;background:var(--color-brand);color:#fff;border:0;border-radius:var(--radius-md);
  padding:7px 14px;font:inherit;font-size:13px;font-weight:500;cursor:pointer}
.btn:hover{background:var(--color-brand-hover)}
.btn--ghost{background:#1F2937;border:1px solid #374151}
body.dark .btn--ghost{background:#2A2F3A;border-color:#4A5266}
.btn .icon{width:16px;height:16px}
main{max-width:1240px;margin:0 auto;padding:var(--space-6) var(--space-6) 120px}
.lede{color:var(--text-secondary);max-width:78ch;margin:0 0 var(--space-4);line-height:1.55}
.lede code{font-family:var(--font-mono);font-size:12px;background:var(--surface-recessed);border:1px solid var(--border-default);border-radius:4px;padding:1px 5px}
.legend{display:flex;flex-wrap:wrap;gap:var(--space-4);margin:0 0 var(--space-6);font-size:12px;color:var(--text-secondary)}
.legend b{font-weight:600}
.conflicts{background:var(--color-warning-bg);border:1px solid var(--color-warning-border);border-left:3px solid var(--color-warning);
  border-radius:0 var(--radius-md) var(--radius-md) 0;padding:10px 14px;margin:0 0 var(--space-6);font-size:13px;color:var(--text-primary)}
.conflicts[hidden]{display:none}
.conflicts h3{margin:0 0 6px;font-size:11px;font-weight:600;text-transform:uppercase;letter-spacing:.07em;color:var(--color-warning)}
.conflicts ul{margin:0;padding-left:18px}
.conflicts code{font-family:var(--font-mono);font-size:12px}
.cat{margin-bottom:var(--space-7)}
.cat__head{display:flex;align-items:baseline;gap:var(--space-3);padding-bottom:var(--space-3);margin-bottom:var(--space-4);border-bottom:.5px solid var(--border-default)}
.cat__title{font-size:13px;font-weight:600;text-transform:uppercase;letter-spacing:.06em;margin:0}
.cat__ref{font-size:11px;color:var(--text-tertiary);font-family:var(--font-mono)}
.cat__count{margin-left:auto;font-size:11px;color:var(--text-tertiary);background:var(--surface-recessed);border:1px solid var(--border-default);border-radius:999px;padding:1px 9px}
.cat__grid{display:grid;grid-template-columns:repeat(auto-fill,minmax(280px,1fr));gap:var(--space-3)}
.card{background:var(--surface-panel);border:.5px solid var(--border-default);border-radius:var(--radius-lg);box-shadow:var(--shadow-sm);
  padding:var(--space-3) var(--space-4);display:flex;flex-direction:column;gap:8px}
.card[data-status=approved]{border-color:var(--color-positive-border);box-shadow:inset 3px 0 0 var(--color-positive)}
.card[data-status=change]{border-color:var(--color-brand-border);box-shadow:inset 3px 0 0 var(--color-brand)}
.card[data-status=review]{border-color:var(--color-warning-border);box-shadow:inset 3px 0 0 var(--color-warning)}
.card.is-conflict{outline:2px solid var(--color-warning);outline-offset:-1px}
.card__top{display:flex;align-items:center;gap:var(--space-3)}
.card__glyph{display:flex;align-items:center;justify-content:center;width:40px;height:40px;flex-shrink:0;background:var(--color-brand-faint);border-radius:var(--radius-md);color:var(--color-brand)}
.card__meta{display:flex;flex-direction:column;gap:1px;min-width:0}
.card__label{font-weight:600;font-size:13px}
.card__id{font-family:var(--font-mono);font-size:11px;color:var(--text-secondary)}
.card__lucide{font-family:var(--font-mono);font-size:10px;color:var(--text-tertiary)}
.card__conflict{margin-left:auto;align-self:flex-start;font-size:9px;font-weight:600;text-transform:uppercase;letter-spacing:.06em;
  color:var(--color-warning);background:var(--color-warning-bg);border:1px solid var(--color-warning-border);border-radius:var(--radius-sm);padding:2px 6px}
.card__conflict[hidden]{display:none}
.card__usage{margin:0;font-size:11px;color:var(--text-tertiary);line-height:1.4}
.card__opts{display:flex;flex-wrap:wrap;gap:6px;padding-top:2px;border-top:.5px solid var(--border-default);margin-top:2px;padding-top:8px}
.opt{display:flex;align-items:center;justify-content:center;width:34px;height:34px;background:var(--surface-recessed);
  border:1px solid var(--border-default);border-radius:var(--radius-md);color:var(--text-secondary);cursor:pointer;padding:0}
.opt:hover{border-color:var(--border-strong);color:var(--text-primary)}
.opt:focus-visible{outline:0;box-shadow:var(--ring-focus)}
.opt.is-chosen{background:var(--color-brand-faint);border-color:var(--color-brand);color:var(--color-brand)}
.opt .icon{width:18px;height:18px}
.card__review{display:flex;align-items:center;gap:var(--space-2);flex-wrap:wrap}
.status{display:inline-flex;border:1px solid var(--border-default);border-radius:var(--radius-md);overflow:hidden}
.status__btn{font:inherit;font-size:11px;font-weight:500;padding:4px 9px;background:var(--surface-panel);color:var(--text-secondary);border:0;border-right:1px solid var(--border-default);cursor:pointer}
.status__btn:last-child{border-right:0}
.status__btn:hover{background:var(--surface-recessed)}
.status__btn.on[data-status=approved]{background:var(--color-positive-bg);color:var(--color-positive)}
.status__btn.on[data-status=change]{background:var(--color-brand-faint);color:var(--color-brand)}
.status__btn.on[data-status=review]{background:var(--color-warning-bg);color:var(--color-warning)}
.note{flex:1;min-width:90px;font:inherit;font-size:12px;background:var(--surface-recessed);border:1px solid var(--border-default);border-radius:var(--radius-md);padding:5px 9px;color:inherit}
.note:focus{outline:0;border-color:var(--color-brand);box-shadow:var(--ring-focus)}
.empty{display:none;color:var(--text-tertiary);padding:var(--space-6);text-align:center}
.statusbar{position:fixed;bottom:0;left:0;right:0;z-index:20;display:flex;align-items:center;gap:var(--space-4);height:48px;padding:0 var(--space-6);
  background:var(--surface-nav);border-top:.5px solid var(--border-default);font-size:12px;font-family:var(--font-mono);color:var(--text-secondary)}
.tally b{font-family:var(--font-ui)}
.dot{display:inline-block;width:8px;height:8px;border-radius:50%;margin-right:5px;vertical-align:middle}
.dot--ok{background:var(--color-positive)} .dot--ch{background:var(--color-brand)} .dot--rv{background:var(--color-warning)} .dot--pd{background:var(--text-disabled)}
.toast{position:fixed;bottom:64px;left:50%;transform:translateX(-50%) translateY(20px);background:var(--text-primary);color:var(--surface-page);
  font-size:12px;font-family:var(--font-mono);padding:8px 14px;border-radius:var(--radius-md);opacity:0;pointer-events:none;transition:opacity .18s,transform .18s;z-index:100}
.toast.show{opacity:1;transform:translateX(-50%) translateY(0)}
</style>
</head>
<body>
${glyphSprite}
<header class="topbar">
  <span class="topbar__title">${esc(manifest.meta.name)}</span>
  <span class="topbar__meta">v${esc(manifest.meta.version)} · Lucide ${esc(iconSetVersion)} · ${allIcons.length} icons</span>
  <span class="spacer"></span>
  <label class="search">
    <svg class="icon" aria-hidden="true"><use href="#g-search"></use></svg>
    <input id="q" type="search" placeholder="Filter…" autocomplete="off" aria-label="Filter icons">
  </label>
  <button class="btn btn--ghost" id="theme" type="button"><svg class="icon" aria-hidden="true"><use href="#g-eye"></use></svg><span id="theme-label">Dark</span></button>
  <button class="btn" id="export" type="button"><svg class="icon" aria-hidden="true"><use href="#g-download"></use></svg>Export review</button>
</header>
<main>
  <p class="lede">Review each icon. Click an <strong>alternative glyph</strong> to choose it, set a decision (<strong>Approve / Change / Review</strong>), and add a note. Choices that put two meanings on the <strong>same glyph</strong> are flagged live, below and on the card. Reference icons in code by semantic id only — <code>&lt;use href="#i-app-studio"&gt;</code>. When done, <strong>Export review</strong> and send me the JSON; I'll fold it back into <code>icons.json</code>.</p>
  <div class="legend">
    <span><span class="dot dot--ok"></span><b>Approve</b> — keep as-is</span>
    <span><span class="dot dot--ch"></span><b>Change</b> — pick a different glyph</span>
    <span><span class="dot dot--rv"></span><b>Review</b> — flag for discussion</span>
    <span><span class="dot dot--pd"></span>Pending — not yet decided</span>
  </div>
  <div class="conflicts" id="conflicts" hidden>
    <h3>Glyph conflicts — same icon used for multiple meanings</h3>
    <ul id="conflicts-list"></ul>
  </div>
${manifest.categories.map(sectionEl).join('')}
  <div class="empty" id="empty">No icons match that filter.</div>
</main>
<div class="statusbar">
  <span class="tally" id="tally"></span><span class="spacer"></span>
  <span id="conflict-count"></span>
</div>
<div class="toast" id="toast"></div>
<script>
const cards=[...document.querySelectorAll('.card')];
const state={}; // id -> {chosen,status,note}
cards.forEach(c=>{state[c.dataset.id]={chosen:c.dataset.primary,status:'pending',note:''};});

// init: mark primary option chosen
cards.forEach(c=>{const p=c.dataset.primary;c.querySelectorAll('.opt').forEach(o=>{if(o.dataset.lucide===p)o.classList.add('is-chosen');});});

function setChosen(card,lucide){
  const id=card.dataset.id;state[id].chosen=lucide;
  card.querySelector('[data-chosen-use]').setAttribute('href','#g-'+lucide);
  card.querySelector('[data-chosen-name]').textContent=lucide;
  card.querySelectorAll('.opt').forEach(o=>o.classList.toggle('is-chosen',o.dataset.lucide===lucide));
  // choosing a non-primary implies a change
  if(lucide!==card.dataset.primary && state[id].status==='pending') setStatus(card,'change');
  recompute();
}
function setStatus(card,status){
  const id=card.dataset.id;state[id].status=status;card.dataset.status=status;
  card.querySelectorAll('.status__btn').forEach(b=>b.classList.toggle('on',b.dataset.status===status));
  tally();
}
cards.forEach(card=>{
  card.querySelectorAll('.opt').forEach(o=>o.addEventListener('click',()=>setChosen(card,o.dataset.lucide)));
  card.querySelectorAll('.status__btn').forEach(b=>b.addEventListener('click',()=>setStatus(card,b.dataset.status)));
  card.querySelector('.note').addEventListener('input',e=>{state[card.dataset.id].note=e.target.value;});
});

function recompute(){
  const map={};
  for(const c of cards){const g=state[c.dataset.id].chosen;(map[g]??=[]).push(c.dataset.id);}
  const groups=Object.entries(map).filter(([,ids])=>ids.length>1);
  const conflicting=new Set(groups.flatMap(([,ids])=>ids));
  for(const c of cards){const on=conflicting.has(c.dataset.id);c.classList.toggle('is-conflict',on);
    const b=c.querySelector('[data-conflict]');b.hidden=!on;}
  const box=document.getElementById('conflicts'),list=document.getElementById('conflicts-list');
  if(groups.length){box.hidden=false;list.innerHTML=groups.map(([g,ids])=>'<li><code>'+g+'</code> → '+ids.map(x=>'<code>i-'+x+'</code>').join(', ')+'</li>').join('');}
  else box.hidden=true;
  document.getElementById('conflict-count').innerHTML=groups.length?('<span class="dot dot--rv"></span>'+groups.length+' glyph conflict'+(groups.length>1?'s':'')):'<span class="dot dot--ok"></span>no conflicts';
}
function tally(){
  const t={approved:0,change:0,review:0,pending:0};
  for(const id in state)t[state[id].status]++;
  document.getElementById('tally').innerHTML=
    '<span class="dot dot--ok"></span><b>'+t.approved+'</b> approved &nbsp; '+
    '<span class="dot dot--ch"></span><b>'+t.change+'</b> change &nbsp; '+
    '<span class="dot dot--rv"></span><b>'+t.review+'</b> review &nbsp; '+
    '<span class="dot dot--pd"></span><b>'+t.pending+'</b> pending';
}

// filter
const q=document.getElementById('q'),cats=[...document.querySelectorAll('[data-cat]')],empty=document.getElementById('empty');
q.addEventListener('input',()=>{const t=q.value.trim().toLowerCase();let any=false;
  for(const c of cats){let shown=0;for(const card of c.querySelectorAll('.card')){const m=!t||card.dataset.search.includes(t);card.style.display=m?'':'none';if(m)shown++;}
    c.style.display=shown?'':'none';if(shown)any=true;}
  empty.style.display=any?'none':'block';});

// theme
const themeBtn=document.getElementById('theme'),themeLabel=document.getElementById('theme-label');
themeBtn.addEventListener('click',()=>{const d=document.body.classList.toggle('dark');themeLabel.textContent=d?'Light':'Dark';});

// export
const toast=document.getElementById('toast');let toastT;
function flash(m){toast.textContent=m;toast.classList.add('show');clearTimeout(toastT);toastT=setTimeout(()=>toast.classList.remove('show'),1600);}
document.getElementById('export').addEventListener('click',async()=>{
  const decisions={};for(const id in state){const s=state[id];decisions[id]={chosen:s.chosen,status:s.status,note:s.note};}
  const out=JSON.stringify({reviewer:'',decisions},null,2);
  try{await navigator.clipboard.writeText(out);flash('Review JSON copied to clipboard');}catch(e){
    const blob=new Blob([out],{type:'application/json'});const a=document.createElement('a');a.href=URL.createObjectURL(blob);a.download='icon-review.json';a.click();flash('Downloaded icon-review.json');}
});

recompute();tally();
</script>
</body>
</html>
`
await writeFile(join(HERE, 'catalog.html'), page)
process.stdout.write(`Wrote catalog.html (${manifest.categories.length} categories, ${allIcons.length} icons, ${conflicts.length} reuse flags)\n`)
