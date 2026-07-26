import { describe, it, expect, vi, beforeEach } from 'vitest'

vi.mock('./firebase', () => ({ db: {} }))

const getDocs = vi.fn()
const collection = vi.fn()
const query = vi.fn()
const orderBy = vi.fn()
const limit = vi.fn()
const addDoc = vi.fn()
const serverTimestamp = vi.fn(() => 'server-ts')

class FakeTimestamp {
  private readonly ms: number
  constructor(ms: number) {
    this.ms = ms
  }
  toDate() {
    return new Date(this.ms)
  }
}

vi.mock('firebase/firestore', () => ({
  getDocs: (...args: unknown[]) => getDocs(...args),
  collection: (...args: unknown[]) => collection(...args),
  query: (...args: unknown[]) => query(...args),
  orderBy: (...args: unknown[]) => orderBy(...args),
  limit: (...args: unknown[]) => limit(...args),
  addDoc: (...args: unknown[]) => addDoc(...args),
  serverTimestamp: () => serverTimestamp(),
  Timestamp: FakeTimestamp,
}))

const { buildContinuityBriefing, saveSessionTranscript } = await import('./sessionMemory')

function snapWithDocs(docs: Array<Record<string, unknown>>) {
  return { docs: docs.map((data) => ({ data: () => data })) }
}

describe('buildContinuityBriefing', () => {
  beforeEach(() => {
    getDocs.mockReset()
  })

  it('says it is the first conversation when there is no prior session', async () => {
    getDocs.mockResolvedValue(snapWithDocs([]))
    const briefing = await buildContinuityBriefing('uid-1')
    expect(briefing).toContain('This is your first conversation with them.')
  })

  it('embeds the prior transcript and a human gap description when a prior session exists', async () => {
    const twoHoursAgo = new FakeTimestamp(Date.now() - 2 * 60 * 60 * 1000)
    getDocs.mockResolvedValue(
      snapWithDocs([{ transcript: 'we talked about cravings', createdAt: twoHoursAgo }]),
    )
    const briefing = await buildContinuityBriefing('uid-1')
    expect(briefing).toContain('we talked about cravings')
    expect(briefing).toMatch(/about \d+ hours? ago/)
  })

  it('degrades gracefully and still returns a usable briefing when the Firestore read rejects', async () => {
    getDocs.mockRejectedValue(new Error('firestore unavailable'))
    const briefing = await buildContinuityBriefing('uid-1')
    expect(briefing).toContain('GREET THEM FIRST')
    expect(typeof briefing).toBe('string')
    expect(briefing.length).toBeGreaterThan(0)
  })

  it('always instructs the model to greet first', async () => {
    getDocs.mockResolvedValue(snapWithDocs([]))
    const briefing = await buildContinuityBriefing('uid-1')
    expect(briefing).toContain('GREET THEM FIRST')
  })
})

describe('saveSessionTranscript', () => {
  beforeEach(() => {
    addDoc.mockReset()
  })

  it('skips empty transcripts', async () => {
    await saveSessionTranscript('uid-1', '')
    expect(addDoc).not.toHaveBeenCalled()
  })

  it('skips whitespace-only transcripts', async () => {
    await saveSessionTranscript('uid-1', '   \n\t  ')
    expect(addDoc).not.toHaveBeenCalled()
  })

  it('truncates very long transcripts to the last MAX_TRANSCRIPT_CHARS characters', async () => {
    const long = 'a'.repeat(3000) + 'b'.repeat(2000) // 5000 chars total
    await saveSessionTranscript('uid-1', long)
    expect(addDoc).toHaveBeenCalledTimes(1)
    const payload = addDoc.mock.calls[0][1] as { transcript: string }
    expect(payload.transcript.length).toBe(4000)
    // Should keep the tail, not the head.
    expect(payload.transcript.endsWith('b'.repeat(2000))).toBe(true)
    // slice(-4000) of 3000 a's + 2000 b's drops exactly the first 1000 a's.
    expect(payload.transcript.includes('a'.repeat(2001))).toBe(false)
    expect(payload.transcript.startsWith('a'.repeat(2000))).toBe(true)
  })

  it('saves a short transcript untruncated', async () => {
    await saveSessionTranscript('uid-1', 'short chat')
    expect(addDoc).toHaveBeenCalledTimes(1)
    const payload = addDoc.mock.calls[0][1] as { transcript: string }
    expect(payload.transcript).toBe('short chat')
  })
})
