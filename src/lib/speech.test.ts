import { describe, it, expect, vi, beforeEach, afterEach } from 'vitest'
import { speak, stopSpeaking } from './speech'

describe('speech', () => {
  let cancel: ReturnType<typeof vi.fn>
  let speakFn: ReturnType<typeof vi.fn>
  let getVoices: ReturnType<typeof vi.fn>

  beforeEach(() => {
    cancel = vi.fn()
    speakFn = vi.fn()
    getVoices = vi.fn(() => [])

    vi.stubGlobal('speechSynthesis', { cancel, speak: speakFn, getVoices })
    vi.stubGlobal(
      'SpeechSynthesisUtterance',
      vi.fn().mockImplementation(function (this: Record<string, unknown>, text: string) {
        this.text = text
        this.rate = 1
        this.pitch = 1
        this.voice = null
      }),
    )
  })

  afterEach(() => {
    vi.unstubAllGlobals()
  })

  it('sets a rate deliberately below the default (1) for crisis pacing', () => {
    speak('you are safe')

    expect(speakFn).toHaveBeenCalledTimes(1)
    const utterance = speakFn.mock.calls[0][0] as { rate: number }
    expect(utterance.rate).toBeLessThan(1)
    expect(utterance.rate).toBeCloseTo(0.82)
  })

  it('no-ops safely when speechSynthesis is not available on window', () => {
    vi.unstubAllGlobals()
    // jsdom does not implement the Web Speech API by default, so this
    // reflects the real "unsupported browser" condition.
    expect('speechSynthesis' in window).toBe(false)

    expect(() => speak('hello')).not.toThrow()
    expect(() => stopSpeaking()).not.toThrow()
  })

  it('cancels any in-progress utterance before speaking the new one', () => {
    speak('first message')

    expect(cancel).toHaveBeenCalledTimes(1)
    expect(speakFn).toHaveBeenCalledTimes(1)
    // cancel must run before the new utterance is queued
    const cancelOrder = cancel.mock.invocationCallOrder[0]
    const speakOrder = speakFn.mock.invocationCallOrder[0]
    expect(cancelOrder).toBeLessThan(speakOrder)
  })

  it('stopSpeaking cancels playback', () => {
    stopSpeaking()
    expect(cancel).toHaveBeenCalledTimes(1)
  })

  it('does not let a throwing synthesis API propagate out of speak()', () => {
    const warnSpy = vi.spyOn(console, 'warn').mockImplementation(() => {})
    speakFn.mockImplementation(() => {
      throw new Error('synthesis engine exploded')
    })

    expect(() => speak('hello')).not.toThrow()
    expect(warnSpy).toHaveBeenCalled()

    warnSpy.mockRestore()
  })

  it('does not let a throwing cancel() propagate out of stopSpeaking()', () => {
    cancel.mockImplementation(() => {
      throw new Error('nothing to cancel')
    })

    expect(() => stopSpeaking()).not.toThrow()
  })
})
