#!/usr/bin/env node
// Fold an exported icon-review.json back into icons.json.
//
//   node apply-review.mjs [review-file]   (default: icon-review.json)
//
// For each decision: set the icon's primary `lucide` to `chosen`, keep the
// previous glyph + alternatives as `alt` (deduped, chosen removed), and stamp
// `status` + `note`. Then print the resulting glyph-reuse conflicts.

import { readFile, writeFile } from 'node:fs/promises'
import { fileURLToPath } from 'node:url'
import { dirname, join } from 'node:path'

const HERE = dirname(fileURLToPath(import.meta.url))
const reviewFile = process.argv[2] || 'icon-review.json'
const manifest = JSON.parse(await readFile(join(HERE, 'icons.json'), 'utf8'))
const review = JSON.parse(await readFile(join(HERE, reviewFile), 'utf8'))
const D = review.decisions

let changed = 0, approved = 0, flagged = 0, missing = []
for (const cat of manifest.categories) {
  for (const i of cat.icons) {
    const d = D[i.id]
    if (!d) { missing.push(i.id); continue }
    const prevPrimary = i.lucide
    const prevAlt = i.alt || []
    i.lucide = d.chosen
    // alt = previous primary + previous alts, minus the new chosen, deduped, order-stable
    i.alt = [...new Set([prevPrimary, ...prevAlt])].filter((n) => n !== d.chosen)
    i.status = d.status
    if (d.note) i.note = d.note; else delete i.note
    if (d.status === 'approved') approved++
    else if (d.status === 'review') flagged++
    if (d.chosen !== prevPrimary) changed++
  }
}

await writeFile(join(HERE, 'icons.json'), JSON.stringify(manifest, null, 2) + '\n')

// conflict report on the applied choices
const all = manifest.categories.flatMap((c) => c.icons)
const byGlyph = {}
for (const i of all) (byGlyph[i.lucide] ??= []).push(i)
const conflicts = Object.entries(byGlyph).filter(([, ids]) => ids.length > 1)

const out = process.stdout
out.write(`Applied review: ${approved} approved, ${changed} glyph changes, ${flagged} flagged for review\n`)
if (missing.length) out.write(`  ⚠ no decision for: ${missing.join(', ')}\n`)
out.write(`\nGlyph reuse after applying (${conflicts.length}):\n`)
for (const [g, icons] of conflicts) {
  const sameCat = new Set(icons.map((i) => catOf(manifest, i.id))).size === 1
  out.write(`  ${g.padEnd(20)} ${icons.map((i) => 'i-' + i.id).join(', ')}${sameCat ? '' : '   [cross-category]'}\n`)
}
out.write(`\nFlagged for review:\n`)
for (const i of all) if (i.status === 'review') out.write(`  i-${i.id.padEnd(24)} → ${i.lucide.padEnd(16)} ${i.note ? '// ' + i.note : ''}\n`)

function catOf(m, id) {
  for (const c of m.categories) if (c.icons.some((i) => i.id === id)) return c.id
  return null
}
