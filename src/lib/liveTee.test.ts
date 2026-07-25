import { describe, it, expect, vi, beforeEach } from 'vitest'
import type { LiveSession } from 'firebase/ai'
import { teeSession } from './liveTee'

interface FakeMessage {
  seq: number
  payload: string
}

function createFakeSession(messages: FakeMessage[]) {
  const label = 'session-label'
  const fakeSession = {
    isClosed: false,
    label,
    async *receive() {
      for (const m of messages) {
        yield m
      }
    },
    // A method that relies on `this` to prove the proxy keeps methods bound
    // to the real target even when destructured off the proxy.
    describeSelf(this: { label: string }) {
      return `session:${this.label}`
    },
  }
  return fakeSession
}

async function collect<T>(gen: AsyncGenerator<T>): Promise<T[]> {
  const out: T[] = []
  for await (const item of gen) {
    out.push(item)
  }
  return out
}

describe('teeSession', () => {
  let messages: FakeMessage[]

  beforeEach(() => {
    messages = [
      { seq: 1, payload: 'a' },
      { seq: 2, payload: 'b' },
      { seq: 3, payload: 'c' },
    ]
  })

  it('forwards every message through unchanged and in order', async () => {
    const fakeSession = createFakeSession(messages)
    const onMessage = vi.fn()
    const proxied = teeSession(fakeSession as unknown as LiveSession, onMessage)

    const received = await collect(proxied.receive() as AsyncGenerator<FakeMessage>)

    expect(received).toHaveLength(3)
    // Same object references, not clones — nothing about the payload changed.
    expect(received[0]).toBe(messages[0])
    expect(received[1]).toBe(messages[1])
    expect(received[2]).toBe(messages[2])
  })

  it('mirrors every message to onMessage in the same order', async () => {
    const fakeSession = createFakeSession(messages)
    const onMessage = vi.fn()
    const proxied = teeSession(fakeSession as unknown as LiveSession, onMessage)

    await collect(proxied.receive() as AsyncGenerator<FakeMessage>)

    expect(onMessage).toHaveBeenCalledTimes(3)
    expect(onMessage.mock.calls.map((c) => c[0])).toEqual(messages)
  })

  it('returns the SAME generator on repeated receive() calls, so only one consumer is created', async () => {
    const fakeSession = createFakeSession(messages)
    const receiveSpy = vi.spyOn(fakeSession, 'receive')
    const onMessage = vi.fn()
    const proxied = teeSession(fakeSession as unknown as LiveSession, onMessage)

    const gen1 = proxied.receive()
    const gen2 = proxied.receive()
    expect(gen1).toBe(gen2)

    // The real session.receive() generator function body only starts running
    // (and is only invoked) once consumption begins, and must never be
    // invoked a second time even though .receive() was called twice above.
    await collect(gen1 as AsyncGenerator<FakeMessage>)
    expect(receiveSpy).toHaveBeenCalledTimes(1)
  })

  it('keeps yielding messages even when onMessage throws', async () => {
    const fakeSession = createFakeSession(messages)
    const onMessage = vi.fn((m: FakeMessage) => {
      if (m.seq === 2) throw new Error('handler blew up')
    })
    const warnSpy = vi.spyOn(console, 'warn').mockImplementation(() => {})

    const proxied = teeSession(fakeSession as unknown as LiveSession, onMessage)
    const received = await collect(proxied.receive() as AsyncGenerator<FakeMessage>)

    expect(received).toEqual(messages)
    expect(onMessage).toHaveBeenCalledTimes(3)
    expect(warnSpy).toHaveBeenCalled()

    warnSpy.mockRestore()
  })

  it('proxies non-receive properties and methods, keeping methods bound to the target', () => {
    const fakeSession = createFakeSession(messages)
    const onMessage = vi.fn()
    const proxied = teeSession(fakeSession as unknown as LiveSession, onMessage)

    // Plain property passthrough.
    expect((proxied as unknown as { isClosed: boolean }).isClosed).toBe(false)

    // Method passthrough, and it must stay bound to the real target even when
    // torn off the proxy (destructured), since consumers may pass callbacks
    // around independently of the proxy object.
    const { describeSelf } = proxied as unknown as { describeSelf: () => string }
    expect(describeSelf()).toBe('session:session-label')
  })
})
