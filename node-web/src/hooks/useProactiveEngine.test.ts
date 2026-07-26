import { describe, it, expect, vi, beforeEach, afterEach } from 'vitest'
import { act, renderHook } from '@testing-library/react'
import { useProactiveEngine } from './useProactiveEngine'

/** A timestamp whose local hour is safely outside HIGH_RISK_HOURS (21,22,23,0-3). */
function noonTimestamp() {
  const d = new Date()
  d.setHours(12, 0, 0, 0)
  return d.getTime()
}

/** A timestamp whose local hour falls inside HIGH_RISK_HOURS. */
function highRiskTimestamp() {
  const d = new Date()
  d.setHours(23, 0, 0, 0)
  return d.getTime()
}

describe('useProactiveEngine', () => {
  beforeEach(() => {
    vi.useFakeTimers()
  })

  afterEach(() => {
    vi.useRealTimers()
  })

  it('fires onTrigger when more than 4 taps land inside the 3s rolling window', () => {
    vi.setSystemTime(noonTimestamp())
    const onTrigger = vi.fn()
    const { result } = renderHook(() => useProactiveEngine(onTrigger, true))

    act(() => {
      for (let i = 0; i < 5; i++) {
        result.current.registerInteraction()
      }
    })

    expect(onTrigger).toHaveBeenCalledTimes(1)
  })

  it('does not fire when taps are spread out beyond the rolling window', () => {
    vi.setSystemTime(noonTimestamp())
    const onTrigger = vi.fn()
    const { result } = renderHook(() => useProactiveEngine(onTrigger, true))

    act(() => {
      for (let i = 0; i < 5; i++) {
        result.current.registerInteraction()
        vi.advanceTimersByTime(3_500) // outlives the 3s frantic window every time
      }
    })

    expect(onTrigger).not.toHaveBeenCalled()
  })

  it('suppresses a second trigger fired again before the cooldown elapses', () => {
    vi.setSystemTime(noonTimestamp())
    const onTrigger = vi.fn()
    const { result } = renderHook(() => useProactiveEngine(onTrigger, true))

    act(() => {
      for (let i = 0; i < 5; i++) result.current.registerInteraction()
    })
    expect(onTrigger).toHaveBeenCalledTimes(1)

    // Well within the 120s cooldown.
    act(() => {
      vi.advanceTimersByTime(1_000)
      for (let i = 0; i < 5; i++) result.current.registerInteraction()
    })

    expect(onTrigger).toHaveBeenCalledTimes(1)
  })

  it('never fires while enabled is false, no matter how frantic the tapping', () => {
    vi.setSystemTime(noonTimestamp())
    const onTrigger = vi.fn()
    const { result } = renderHook(() => useProactiveEngine(onTrigger, false))

    act(() => {
      for (let i = 0; i < 10; i++) result.current.registerInteraction()
      vi.advanceTimersByTime(200_000)
    })

    expect(onTrigger).not.toHaveBeenCalled()
  })

  it('fires idle detection when silence crosses the limit during a high-risk hour', () => {
    vi.setSystemTime(highRiskTimestamp())
    const onTrigger = vi.fn()
    renderHook(() => useProactiveEngine(onTrigger, true))

    act(() => {
      vi.advanceTimersByTime(90_000) // IDLE_LIMIT_MS, no interaction registered
    })

    expect(onTrigger).toHaveBeenCalledTimes(1)
  })

  it('does not fire idle detection for the same silence outside high-risk hours', () => {
    vi.setSystemTime(noonTimestamp())
    const onTrigger = vi.fn()
    renderHook(() => useProactiveEngine(onTrigger, true))

    act(() => {
      vi.advanceTimersByTime(90_000)
    })

    expect(onTrigger).not.toHaveBeenCalled()
  })
})
