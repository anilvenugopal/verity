import { describe, it, expect } from 'vitest'
import { FIELDS } from '../assessmentCatalog'

// Every key passed to sel() / bool() in AssessmentForm.tsx must exist in FIELDS.
// This is the test that would have caught the 'classification' crash in session 003
// (FIELDS['classification'] was undefined because the key was missing from the catalog).
const SEL_KEYS = [
  'decision_type', 'consumer_effect', 'deployment_scale',
  // DataItem sel() calls
  'direction', 'data_type', 'source', 'classification', 'pii_presence',
  // OversightControl sel()
  'autonomy_level', 'stage',
  // RiskItem sel()
  'category', 'likelihood', 'severity', 'residual',
]

const BOOL_KEYS = [
  'annex_iii_high_risk', 'solely_automated', 'affected_populations',
  'stop_mechanism', 'can_override',
  'disparate_impact_tested',
]

describe('assessmentCatalog FIELDS', () => {
  it('every sel() key exists in FIELDS', () => {
    for (const key of SEL_KEYS) {
      expect(FIELDS[key], `FIELDS['${key}'] should exist`).toBeDefined()
    }
  })

  it('every bool() key exists in FIELDS', () => {
    for (const key of BOOL_KEYS) {
      expect(FIELDS[key], `FIELDS['${key}'] should exist`).toBeDefined()
    }
  })

  it('every FIELDS entry has a non-empty label and help', () => {
    for (const [key, field] of Object.entries(FIELDS)) {
      expect(field.label, `FIELDS['${key}'].label`).toBeTruthy()
      expect(field.help,  `FIELDS['${key}'].help`).toBeTruthy()
    }
  })

  it('every entry with options has at least one option with non-empty value and label', () => {
    for (const [key, field] of Object.entries(FIELDS)) {
      if (!field.options) continue
      expect(field.options.length, `FIELDS['${key}'].options length`).toBeGreaterThan(0)
      for (const opt of field.options) {
        expect(opt.value, `FIELDS['${key}'] option.value`).toBeTruthy()
        expect(opt.label, `FIELDS['${key}'] option.label`).toBeTruthy()
      }
    }
  })
})
