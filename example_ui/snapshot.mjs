#!/usr/bin/env node
// Snapshot every pages/*.html at 1440×810 (16:9 landscape), zoomed to 90%.
// Usage: npx puppeteer-core not needed — we use the full puppeteer package
// which downloads a bundled Chromium on install.
//
//   npm i -D puppeteer    (one time, ~150 MB)
//   node snapshot.mjs

import { readdir } from 'node:fs/promises';
import { fileURLToPath, pathToFileURL } from 'node:url';
import { dirname, join } from 'node:path';
import puppeteer from '/home/avenugopal/.npm-global/lib/node_modules/puppeteer/lib/esm/puppeteer/puppeteer.js';

const HERE   = dirname(fileURLToPath(import.meta.url));
const PAGES  = join(HERE, 'pages');
const OUTDIR = join(HERE, 'snapshots');

const ZOOM = 0.9;

// Default desktop snapshot for every page (1440×810).
// Editor pages also captured at tablet widths to verify the responsive
// behaviour (compact phase pills below 1024px, utility overflow below 1280px).
const DEFAULT = { width: 1440, height: 810, suffix: '' };
const EDITOR_TABLET = [
  { width: 1180, height: 810, suffix: '@1180' },   // iPad landscape
  { width: 1024, height: 810, suffix: '@1024' },   // boundary — phases collapse
];
const isEditor = f => /^editor-(storm|draft|curate|polish|proof|publish|focus|preview)\.html$/.test(f);

const files = (await readdir(PAGES)).filter(f => f.endsWith('.html')).sort();

const browser = await puppeteer.launch({
  headless: 'new',
  args: ['--no-sandbox', '--disable-setuid-sandbox'],
});

async function snap(f, vp) {
  const page = await browser.newPage();
  await page.setViewport({ width: vp.width, height: vp.height, deviceScaleFactor: 2 });
  const url = pathToFileURL(join(PAGES, f)).href;
  await page.goto(url, { waitUntil: 'networkidle0', timeout: 30_000 });
  await page.evaluate(z => { document.documentElement.style.zoom = String(z); }, ZOOM);
  await new Promise(r => setTimeout(r, 400));
  const out = join(OUTDIR, f.replace(/\.html$/, `${vp.suffix}.png`));
  await page.screenshot({ path: out, type: 'png', clip: { x: 0, y: 0, width: vp.width, height: vp.height } });
  console.log(`✓ ${f}${vp.suffix} → snapshots/${f.replace(/\.html$/, `${vp.suffix}.png`)}`);
  await page.close();
}

let count = 0;
for (const f of files) {
  await snap(f, DEFAULT);
  count++;
  if (isEditor(f)) {
    for (const vp of EDITOR_TABLET) {
      await snap(f, vp);
      count++;
    }
  }
}

await browser.close();
console.log(`\nDone — ${count} snapshots in snapshots/`);
