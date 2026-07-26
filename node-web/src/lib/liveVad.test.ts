import { describe, it, expect, vi, beforeEach, afterEach } from 'vitest'
import { connectWithVadConfig, REALTIME_INPUT_CONFIG } from './liveVad'

class FakeWebSocket {
  send(_data: unknown): void {
    // Overwritten by a vi.fn() spy in each test's beforeEach so we can
    // observe exactly what connectWithVadConfig's wrapper forwards to the
    // "real" underlying send.
  }
}

describe('connectWithVadConfig', () => {
  let sendSpy: ReturnType<typeof vi.fn>

  beforeEach(() => {
    sendSpy = vi.fn()
    FakeWebSocket.prototype.send = sendSpy as unknown as typeof FakeWebSocket.prototype.send
    vi.stubGlobal('WebSocket', FakeWebSocket)
  })

  afterEach(() => {
    vi.unstubAllGlobals()
  })

  it('restores the original WebSocket.prototype.send after connect resolves', async () => {
    const originalSend = FakeWebSocket.prototype.send
    await connectWithVadConfig(async () => 'ok')
    expect(FakeWebSocket.prototype.send).toBe(originalSend)
  })

  it('restores the original WebSocket.prototype.send after connect throws', async () => {
    const originalSend = FakeWebSocket.prototype.send
    await expect(
      connectWithVadConfig(async () => {
        throw new Error('boom')
      }),
    ).rejects.toThrow('boom')
    expect(FakeWebSocket.prototype.send).toBe(originalSend)
  })

  it('injects realtimeInputConfig with the expected VAD values into a setup frame', async () => {
    await connectWithVadConfig(async () => {
      const ws = new FakeWebSocket()
      ws.send(JSON.stringify({ setup: { model: 'gemini' } }))
      return null
    })

    expect(sendSpy).toHaveBeenCalledTimes(1)
    const sent = JSON.parse(sendSpy.mock.calls[0][0] as string)
    expect(sent.setup.realtimeInputConfig).toEqual(REALTIME_INPUT_CONFIG)
    expect(sent.setup.realtimeInputConfig.automaticActivityDetection).toEqual({
      silenceDurationMs: 1400,
      prefixPaddingMs: 400,
      endOfSpeechSensitivity: 'END_SENSITIVITY_LOW',
      startOfSpeechSensitivity: 'START_SENSITIVITY_LOW',
    })
  })

  it('passes a non-setup JSON string through byte-identical', async () => {
    const original = JSON.stringify({ notSetup: true, foo: 'bar' })
    await connectWithVadConfig(async () => {
      const ws = new FakeWebSocket()
      ws.send(original)
      return null
    })
    expect(sendSpy).toHaveBeenCalledWith(original)
  })

  it('passes malformed JSON containing "setup" through untouched rather than throwing', async () => {
    const malformed = '{"setup": not valid json'
    let threw = false
    await connectWithVadConfig(async () => {
      const ws = new FakeWebSocket()
      try {
        ws.send(malformed)
      } catch {
        threw = true
      }
      return null
    })
    expect(threw).toBe(false)
    expect(sendSpy).toHaveBeenCalledWith(malformed)
  })

  it('only patches the first setup frame (patched latch)', async () => {
    await connectWithVadConfig(async () => {
      const ws = new FakeWebSocket()
      ws.send(JSON.stringify({ setup: { model: 'gemini' } }))
      ws.send(JSON.stringify({ setup: { model: 'gemini-2' } }))
      return null
    })

    expect(sendSpy).toHaveBeenCalledTimes(2)
    const first = JSON.parse(sendSpy.mock.calls[0][0] as string)
    const second = JSON.parse(sendSpy.mock.calls[1][0] as string)
    expect(first.setup.realtimeInputConfig).toEqual(REALTIME_INPUT_CONFIG)
    // Second setup frame passes through untouched — latch already tripped.
    expect(second.setup.realtimeInputConfig).toBeUndefined()
  })

  it('passes binary/non-string payloads through untouched', async () => {
    const binary = new Uint8Array([1, 2, 3]).buffer
    await connectWithVadConfig(async () => {
      const ws = new FakeWebSocket()
      ws.send(binary)
      return null
    })
    expect(sendSpy).toHaveBeenCalledWith(binary)
  })
})
