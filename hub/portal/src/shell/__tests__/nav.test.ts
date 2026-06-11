import { describe, it, expect } from 'vitest'
import { NAV, resolveNav, type NavNode } from '../nav'

const alwaysTrue = () => true
const alwaysFalse = () => false

describe('resolveNav', () => {
  it('shows all nodes when can() always returns true', () => {
    const result = resolveNav(NAV, alwaysTrue)
    expect(result.length).toBeGreaterThan(0)
    expect(result.length).toBe(NAV.length)
  })

  it('hides gated nodes when can() returns false', () => {
    // The intake app has two gated action children (requires: 'onboard_application', 'create_intake')
    const intake = resolveNav(NAV, alwaysTrue).find((n) => n.key === 'intake')!
    const withGate = intake.children!
    const withoutGate = resolveNav(
      NAV,
      (req) => req !== 'onboard_application' && req !== 'create_intake',
    ).find((n) => n.key === 'intake')!.children!

    expect(withGate.some((c) => c.key === 'onboard-app')).toBe(true)
    expect(withGate.some((c) => c.key === 'intake-uc')).toBe(true)
    expect(withoutGate.some((c) => c.key === 'onboard-app')).toBe(false)
    expect(withoutGate.some((c) => c.key === 'intake-uc')).toBe(false)
  })

  it('resolves children recursively', () => {
    const result = resolveNav(NAV, alwaysTrue)
    const intake = result.find((n) => n.key === 'intake')
    expect(intake?.children).toBeDefined()
    expect(intake!.children!.length).toBeGreaterThan(0)
  })

  it('intake app has ownedPaths: [\'/intakes\']', () => {
    const intake = NAV.find((n) => n.key === 'intake')
    expect(intake?.ownedPaths).toContain('/intakes')
  })

  it('postProcess injected nodes are re-gated', () => {
    // Inject a node with requires:'secret' — alwaysFalse gate should remove it
    const injected: NavNode = { key: 'injected', kind: 'page', label: 'Injected', icon: 'i-test', requires: 'secret' }
    const result = resolveNav(NAV, alwaysFalse, (nodes) => [...nodes, injected])
    expect(result.some((n) => n.key === 'injected')).toBe(false)
  })

  it('postProcess can add ungated nodes', () => {
    const injected: NavNode = { key: 'ungated', kind: 'page', label: 'Ungated', icon: 'i-test' }
    const result = resolveNav(NAV, alwaysFalse, (nodes) => [...nodes, injected])
    expect(result.some((n) => n.key === 'ungated')).toBe(true)
  })
})
