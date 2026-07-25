import { describe, it, expect, vi } from 'vitest'

// Avoid touching the real Firebase app bootstrap (network config, env vars).
vi.mock('./firebase', () => ({ db: {} }))

// summarizeEvents only depends on `Timestamp` from firebase/firestore; stub the
// rest of the surface patientActivity.ts imports so the module loads cleanly.
vi.mock('firebase/firestore', () => {
  class FakeTimestamp {
    ms: number
    constructor(ms: number) {
      this.ms = ms
    }
    static fromMillis(ms: number) {
      return new FakeTimestamp(ms)
    }
    toMillis() {
      return this.ms
    }
  }
  return {
    Timestamp: FakeTimestamp,
    collection: vi.fn(),
    onSnapshot: vi.fn(),
    orderBy: vi.fn(),
    query: vi.fn(),
    limit: vi.fn(),
  }
})

const { summarizeEvents } = await import('./patientActivity')
const { Timestamp } = await import('firebase/firestore')

type Event = Parameters<typeof summarizeEvents>[0][number]

function makeEvent(overrides: Partial<Event>): Event {
  return {
    type: 'checkin',
    mood: null,
    createdAt: Timestamp.fromMillis(Date.now()),
    ...overrides,
  } as Event
}

describe('summarizeEvents', () => {
  it('returns the empty-state message for no events', () => {
    expect(summarizeEvents([])).toBe('No activity recorded yet.')
  })

  it('groups and counts events by type into the summary', () => {
    const events = [
      makeEvent({ type: 'checkin' }),
      makeEvent({ type: 'checkin' }),
      makeEvent({ type: 'reset' }),
    ]
    const summary = summarizeEvents(events)
    expect(summary).toContain('2 × mood check-in')
    expect(summary).toContain('1 × emergency reset')
  })

  it('picks the most recent (first in list) non-null mood', () => {
    const events = [
      makeEvent({ type: 'checkin', mood: null }),
      makeEvent({ type: 'checkin', mood: 'anxious' }),
      makeEvent({ type: 'checkin', mood: 'calm' }),
    ]
    const summary = summarizeEvents(events)
    expect(summary).toContain('Most recently tapped mood: anxious.')
    expect(summary).not.toContain('calm.')
  })

  it('does not claim a mood was tapped when every event has a null mood', () => {
    const events = [
      makeEvent({ type: 'checkin', mood: null }),
      makeEvent({ type: 'reset', mood: null }),
    ]
    const summary = summarizeEvents(events)
    expect(summary).toContain('No mood tapped recently.')
    expect(summary).not.toContain('Most recently tapped mood')
  })

  it('falls back to the raw type string for unknown event types', () => {
    const events = [makeEvent({ type: 'mystery_event' as unknown as Event['type'] })]
    const summary = summarizeEvents(events)
    expect(summary).toContain('1 × mystery_event')
  })

  it('computes the time window from the oldest event Timestamp', () => {
    const now = Date.now()
    vi.useFakeTimers()
    vi.setSystemTime(now)
    const events = [
      makeEvent({ createdAt: Timestamp.fromMillis(now) }),
      makeEvent({ createdAt: Timestamp.fromMillis(now - 10 * 60_000) }),
    ]
    const summary = summarizeEvents(events)
    expect(summary).toContain('in the last 10 minutes')
    vi.useRealTimers()
  })

  it('falls back to "recently" when the oldest event has no real Timestamp', () => {
    const events = [makeEvent({ createdAt: undefined })]
    const summary = summarizeEvents(events)
    expect(summary).toContain('recently')
  })
})
