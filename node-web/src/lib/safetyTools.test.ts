import { describe, it, expect } from 'vitest'
import { RELAPSE_RISK_TOOL } from './safetyTools'

describe('RELAPSE_RISK_TOOL', () => {
  const declarations = RELAPSE_RISK_TOOL.functionDeclarations ?? []

  it('declares exactly one function named flagRelapseRisk', () => {
    expect(declarations).toHaveLength(1)
    expect(declarations[0].name).toBe('flagRelapseRisk')
  })

  it('has a non-empty description', () => {
    const decl = declarations[0]
    expect(decl.description).toBeTruthy()
    expect(typeof decl.description).toBe('string')
  })

  it('declares stage and observation parameters', () => {
    const decl = declarations[0]
    // eslint-disable-next-line @typescript-eslint/no-explicit-any
    const props = (decl.parameters as any).properties
    expect(props).toHaveProperty('stage')
    expect(props).toHaveProperty('observation')
  })

  it('the stage enum contains exactly "intervening" and "escalated"', () => {
    const decl = declarations[0]
    // eslint-disable-next-line @typescript-eslint/no-explicit-any
    const stageSchema = (decl.parameters as any).properties.stage
    expect(stageSchema.enum).toEqual(['intervening', 'escalated'])
  })
})
