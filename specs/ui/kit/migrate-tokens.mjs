#!/usr/bin/env node
// One-shot migration: point the prototype wireframes at the canonical tokens.css
// and rename their drifted token vocabularies to the canonical names.
//
//   node kit/migrate-tokens.mjs            (run from specs/ui)
//
// For each wireframe:
//   1. remove the inline :root{…} and .dark{…} token blocks (now owned by tokens.css)
//   2. add <link rel="stylesheet" href="kit/styles/tokens.css"> after the fonts link
//   3. rename every var(--legacy) → var(--canonical)  (terse 1:1, verbose by meaning)
//
// Idempotent: re-running is a no-op once a file is migrated.

import { readFile, writeFile } from 'node:fs/promises'
import { fileURLToPath } from 'node:url'
import { dirname, join } from 'node:path'

const UI = join(dirname(fileURLToPath(import.meta.url)), '..') // specs/ui
const FILES = [
  'verity-design-sample.html',
  'verity-homepage.html',
  'verity-nav-framework.html',
  'verity-agent-studio.html',
  'verity-intake-wireframe.html',
  'triage_agent_failing_cases.html',
  'prompt_editor_diff_v14_v150.html',
  'verity_authoring_canvas_model.html',
]

// legacy → canonical. Longest keys first so prefixes (--blue vs --blue-h) are safe.
const MAP = {
  // verbose (by meaning) — list first; they are the longest names
  '--color-background-primary': '--surface-panel',
  '--color-background-secondary': '--surface-page',
  '--color-background-tertiary': '--surface-recessed',
  '--color-background-info': '--color-brand-wash',
  '--color-background-success': '--color-positive-bg',
  '--color-background-warning': '--color-warning-bg',
  '--color-background-danger': '--color-negative-bg',
  '--color-text-primary': '--text-primary',
  '--color-text-secondary': '--text-secondary',
  '--color-text-tertiary': '--text-tertiary',
  '--color-text-info': '--color-brand',
  '--color-text-success': '--color-positive',
  '--color-text-warning': '--color-warning',
  '--color-text-danger': '--color-negative',
  '--color-border-secondary': '--border-default',
  '--color-border-tertiary': '--border-faint',
  '--color-border-info': '--color-brand-border',
  '--color-border-success': '--color-positive-border',
  '--color-border-warning': '--color-warning-border',
  '--color-border-danger': '--color-negative-border',
  '--border-radius-md': '--radius-md',
  '--border-radius-lg': '--radius-lg',
  '--font-sans': '--font-ui',
  '--shadow-xl': '--shadow-lg',
  // terse (1:1, identical values)
  '--blue-h': '--color-brand-hover',
  '--blue-bg': '--color-brand-faint',
  '--blue-w': '--color-brand-wash',
  '--blue-b': '--color-brand-border',
  '--green-bg': '--color-positive-bg',
  '--green-b': '--color-positive-border',
  '--amber-bg': '--color-warning-bg',
  '--amber-b': '--color-warning-border',
  '--red-bg': '--color-negative-bg',
  '--red-b': '--color-negative-border',
  '--bfaint': '--border-faint',
  '--bstrong': '--border-strong',
  '--hover': '--surface-hover',
  '--panel': '--surface-panel',
  '--blue': '--color-brand',
  '--green': '--color-positive',
  '--amber': '--color-warning',
  '--red': '--color-negative',
  '--nav': '--surface-nav',
  '--rec': '--surface-recessed',
  '--mono': '--font-mono',
  '--font': '--font-ui',
  '--bg': '--surface-page',
  '--t1': '--text-primary',
  '--t2': '--text-secondary',
  '--t3': '--text-tertiary',
  '--t4': '--text-disabled',
  '--r10': '--radius-xl',
  '--r4': '--radius-sm',
  '--r6': '--radius-md',
  '--r8': '--radius-lg',
  '--sh': '--shadow-sm',
  '--shm': '--shadow-md',
  '--border': '--border-default',
}
// apply longest-key-first
const PAIRS = Object.entries(MAP).sort((a, b) => b[0].length - a[0].length)

const FONTS = '<link href="https://fonts.googleapis.com/css2?family=IBM+Plex+Mono:wght@400;500&family=IBM+Plex+Sans:wght@300;400;500;600&display=swap" rel="stylesheet">'
const LINK = '<link rel="stylesheet" href="kit/styles/tokens.css">'

function removeBlock(css, selector) {
  // remove `selector { ... }` — token blocks contain no nested braces
  const re = new RegExp(selector.replace(/[.*+?^${}()|[\]\\]/g, '\\$&') + '\\s*\\{[^}]*\\}\\s*', 'g')
  return css.replace(re, '')
}

let report = []
for (const name of FILES) {
  const path = join(UI, name)
  let html = await readFile(path, 'utf8')
  const before = html

  // 1. strip inline token blocks (first :root and any .dark)
  html = removeBlock(html, ':root')
  html = removeBlock(html, '.dark')

  // 2. add the link once, right after the google-fonts stylesheet link
  if (!html.includes('kit/styles/tokens.css')) {
    if (/<link[^>]*fonts\.googleapis[^>]*>/.test(html)) {
      html = html.replace(/(<link[^>]*fonts\.googleapis[^>]*>)/, `$1\n${LINK}`)
    } else if (/<head[^>]*>/.test(html)) {
      html = html.replace(/(<head[^>]*>)/, `$1\n${FONTS}\n${LINK}`)
    } else if (/<style[^>]*>/.test(html)) {
      // fragment with no <head>: load fonts + tokens before the first <style>
      html = html.replace(/(<style[^>]*>)/, `${FONTS}\n${LINK}\n$1`)
    }
  }

  // 3. rename tokens (word-boundary so prefixes don't collide)
  let renames = 0
  for (const [from, to] of PAIRS) {
    const re = new RegExp(from.replace(/[-]/g, '\\-') + '(?![\\w-])', 'g')
    html = html.replace(re, (m) => { renames++; return to })
  }

  if (html !== before) await writeFile(path, html)
  report.push({ name, changed: html !== before, renames })
}

for (const r of report) process.stdout.write(`${r.changed ? '✓' : '·'} ${r.name.padEnd(40)} ${r.renames} token refs renamed\n`)
