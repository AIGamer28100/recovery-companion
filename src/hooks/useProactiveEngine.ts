import { useCallback, useEffect, useRef, useState } from 'react'

/** Hours that are historically higher-risk; a long silence inside one is a signal. */
const HIGH_RISK_HOURS = [21, 22, 23, 0, 1, 2, 3]

/** Taps within this rolling window count toward "frantic" interaction. */
const FRANTIC_WINDOW_MS = 3_000
const FRANTIC_TAP_THRESHOLD = 4

/** Silence during a high-risk hour that counts as a missed check-in. */
const IDLE_LIMIT_MS = 90_000

/** Don't re-fire a proactive intervention more often than this. */
const COOLDOWN_MS = 120_000

const TICK_MS = 5_000

export interface BehavioralState {
  timeInAppWithoutInteraction: number
  franticTapCount: number
  missedCheckInWindow: boolean
}

/**
 * Watches for signs of rising stress and fires a proactive intervention.
 *
 * All timing is derived from wall-clock `Date.now()` deltas rather than counted
 * interval ticks — background tabs get their timers throttled, which would make
 * tick-counting silently under-report idle time.
 */
export function useProactiveEngine(onTrigger: () => void, enabled: boolean) {
  const tapTimestamps = useRef<number[]>([])
  const lastInteraction = useRef<number>(Date.now())
  const lastTriggered = useRef<number>(0)
  const [state, setState] = useState<BehavioralState>({
    timeInAppWithoutInteraction: 0,
    franticTapCount: 0,
    missedCheckInWindow: false,
  })

  const fire = useCallback(() => {
    const now = Date.now()
    if (now - lastTriggered.current < COOLDOWN_MS) return
    lastTriggered.current = now
    tapTimestamps.current = []
    lastInteraction.current = now
    onTrigger()
  }, [onTrigger])

  /** Call on every meaningful user interaction. */
  const registerInteraction = useCallback(() => {
    const now = Date.now()
    lastInteraction.current = now
    tapTimestamps.current = [...tapTimestamps.current, now].filter(
      (t) => now - t <= FRANTIC_WINDOW_MS,
    )
    const franticTapCount = tapTimestamps.current.length
    setState((s) => ({ ...s, franticTapCount, timeInAppWithoutInteraction: 0 }))

    if (enabled && franticTapCount > FRANTIC_TAP_THRESHOLD) fire()
  }, [enabled, fire])

  useEffect(() => {
    if (!enabled) return
    const id = setInterval(() => {
      const now = Date.now()
      const idleMs = now - lastInteraction.current
      const inHighRiskHour = HIGH_RISK_HOURS.includes(new Date().getHours())
      const missedCheckInWindow = inHighRiskHour && idleMs >= IDLE_LIMIT_MS

      setState((s) => ({
        ...s,
        timeInAppWithoutInteraction: idleMs,
        missedCheckInWindow,
      }))

      if (missedCheckInWindow) fire()
    }, TICK_MS)
    return () => clearInterval(id)
  }, [enabled, fire])

  return { state, registerInteraction }
}
