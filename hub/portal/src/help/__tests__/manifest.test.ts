import { describe, it, expect } from 'vitest'
import { readFileSync, readdirSync, statSync } from 'node:fs'
import { join, dirname } from 'node:path'
import { fileURLToPath } from 'node:url'
import { helpManifest } from '../_manifest'
import { useHelp, useHelpPage } from '../useHelp'

describe('helpManifest — field snippets', () => {
  it('every form field has a non-empty label and help string', () => {
    for (const [formKey, form] of Object.entries(helpManifest.forms)) {
      for (const [fieldKey, snippet] of Object.entries(form.fields)) {
        expect(snippet.label, `${formKey}.fields.${fieldKey}.label`).toBeTruthy()
        expect(snippet.help,  `${formKey}.fields.${fieldKey}.help`).toBeTruthy()
      }
    }
  })

  it('every page entry is a function (loader)', () => {
    for (const [key, form] of Object.entries(helpManifest.forms)) {
      expect(typeof form.page, `forms.${key}.page`).toBe('function')
    }
    for (const [key, wf] of Object.entries(helpManifest.workflows)) {
      expect(typeof wf.page, `workflows.${key}.page`).toBe('function')
    }
    for (const [key, role] of Object.entries(helpManifest.roles)) {
      expect(typeof role.page, `roles.${key}.page`).toBe('function')
    }
  })
})

describe('useHelp', () => {
  it('resolves a known field path', () => {
    const snippet = useHelp('forms.assessment.fields.decision_type')
    expect(snippet).not.toBeNull()
    expect(snippet?.label).toBe('Decision type')
  })

  it('returns null for an unknown path', () => {
    expect(useHelp('forms.assessment.fields.__nonexistent__')).toBeNull()
    expect(useHelp('forms.__nonexistent__')).toBeNull()
    expect(useHelp('')).toBeNull()
  })

  it('resolves fields for every registered form', () => {
    const formKeys = Object.keys(helpManifest.forms)
    for (const formKey of formKeys) {
      const firstField = Object.keys(helpManifest.forms[formKey as keyof typeof helpManifest.forms].fields)[0]
      if (!firstField) continue
      const snippet = useHelp(`forms.${formKey}.fields.${firstField}`)
      expect(snippet, `forms.${formKey}.fields.${firstField} should resolve`).not.toBeNull()
    }
  })
})

describe('useHelpPage', () => {
  it('resolves a page loader for known paths', () => {
    expect(typeof useHelpPage('forms.assessment')).toBe('function')
    expect(typeof useHelpPage('workflows.intake-approval')).toBe('function')
    expect(typeof useHelpPage('overview.glossary')).toBe('function')
  })

  it('returns null for unknown paths', () => {
    expect(useHelpPage('forms.__nonexistent__')).toBeNull()
    expect(useHelpPage('')).toBeNull()
  })
})

describe('helpId call-site integrity', () => {
  it('every helpId string referenced in component source resolves in the manifest', () => {
    // Walk src/ (excluding __tests__) and extract every helpId="..." pattern.
    // Any string that doesn't resolve via useHelp() is a stale or misspelled ID.
    const srcDir = join(dirname(fileURLToPath(import.meta.url)), '../../..')

    function collect(dir: string): string[] {
      const out: string[] = []
      for (const entry of readdirSync(dir)) {
        if (entry === '__tests__' || entry === 'node_modules') continue
        const full = join(dir, entry)
        if (statSync(full).isDirectory()) {
          out.push(...collect(full))
        } else if (entry.endsWith('.tsx') || entry.endsWith('.ts')) {
          out.push(full)
        }
      }
      return out
    }

    const HELP_ID_RE = /helpId=["'`]([^"'`]+)["'`]/g
    const found: string[] = []
    for (const file of collect(srcDir)) {
      const content = readFileSync(file, 'utf-8')
      for (const m of content.matchAll(HELP_ID_RE)) {
        found.push(m[1]!)
      }
    }

    expect(found.length, 'Expected at least one helpId in source files').toBeGreaterThan(0)

    for (const id of found) {
      expect(useHelp(id), `helpId "${id}" not found in helpManifest — update the corpus or fix the typo`).not.toBeNull()
    }
  })
})
