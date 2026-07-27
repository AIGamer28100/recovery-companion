import { describe, it, expect } from 'vitest'
import { retentionExpiresAt, RETENTION_DAYS } from './retention'

describe('retentionExpiresAt', () => {
  it('returns a Date exactly 180 days after the given instant', () => {
    const now = Date.UTC(2026, 0, 1)
    const result = retentionExpiresAt(now)
    expect(RETENTION_DAYS).toBe(180)
    expect(result.getTime() - now).toBe(180 * 24 * 60 * 60 * 1000)
  })

  it('defaults to Date.now() when no instant is passed', () => {
    const before = Date.now()
    const result = retentionExpiresAt()
    const after = Date.now()
    expect(result.getTime()).toBeGreaterThanOrEqual(before + 180 * 24 * 60 * 60 * 1000)
    expect(result.getTime()).toBeLessThanOrEqual(after + 180 * 24 * 60 * 60 * 1000)
  })
})
