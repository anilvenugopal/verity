#!/usr/bin/env node
// Snapshot a single page passed as arg. Usage: node snapshot-one.mjs editor-curate.html
import { fileURLToPath, pathToFileURL } from 'node:url';
import { dirname, join } from 'node:path';
import puppeteer from '/home/avenugopal/.npm-global/lib/node_modules/puppeteer/lib/esm/puppeteer/puppeteer.js';

const HERE   = dirname(fileURLToPath(import.meta.url));
const PAGES  = join(HERE, 'pages');
const OUTDIR = join(HERE, 'snapshots');

const f = process.argv[2];
if (!f) { console.error('usage: node snapshot-one.mjs <file.html>'); process.exit(1); }

const browser = await puppeteer.launch({ headless: 'new', args: ['--no-sandbox', '--disable-setuid-sandbox'] });
const page = await browser.newPage();
await page.setViewport({ width: 1440, height: 810, deviceScaleFactor: 2 });
await page.goto(pathToFileURL(join(PAGES, f)).href, { waitUntil: 'networkidle0', timeout: 30_000 });
await page.evaluate(() => { document.documentElement.style.zoom = '0.9'; });
await new Promise(r => setTimeout(r, 400));
const out = join(OUTDIR, f.replace(/\.html$/, '.png'));
await page.screenshot({ path: out, type: 'png', clip: { x: 0, y: 0, width: 1440, height: 810 } });
console.log(`✓ ${f} → snapshots/${f.replace(/\.html$/, '.png')}`);
await browser.close();