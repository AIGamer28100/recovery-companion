import { describe, it, expect, vi, beforeEach, afterEach } from 'vitest'
import type { LiveSession } from 'firebase/ai'
import { VideoFrameStreamer } from './videoStream'

const DIFF_SIZE = 32 * 24 * 4 // DIFF_W * DIFF_H * RGBA

function makePixelBuffer(value: number): Uint8ClampedArray {
  return new Uint8ClampedArray(DIFF_SIZE).fill(value)
}

describe('VideoFrameStreamer', () => {
  let pixelData: Uint8ClampedArray
  let getContextSpy: ReturnType<typeof vi.spyOn>
  let toDataURLSpy: ReturnType<typeof vi.spyOn>
  let sendVideoRealtime: ReturnType<typeof vi.fn>
  let session: { isClosed: boolean; sendVideoRealtime: ReturnType<typeof vi.fn> }
  let video: { videoWidth: number; videoHeight: number }

  beforeEach(() => {
    vi.useFakeTimers()
    pixelData = makePixelBuffer(100)

    const diffCtx = {
      drawImage: vi.fn(),
      getImageData: vi.fn(() => ({ data: pixelData })),
    }
    const mainCtx = {
      drawImage: vi.fn(),
    }

    // The diff canvas is fixed at 32x24 by the constructor; the main capture
    // canvas is only resized to FRAME_WIDTH (512) right before it's used, so
    // width reliably distinguishes which canvas is asking for a context.
    getContextSpy = vi
      .spyOn(HTMLCanvasElement.prototype, 'getContext')
      .mockImplementation(function (this: HTMLCanvasElement) {
        return (this.width === 32 ? diffCtx : mainCtx) as unknown as CanvasRenderingContext2D
      })

    toDataURLSpy = vi
      .spyOn(HTMLCanvasElement.prototype, 'toDataURL')
      .mockReturnValue('data:image/jpeg;base64,ZmFrZQ==')

    sendVideoRealtime = vi.fn().mockResolvedValue(undefined)
    session = { isClosed: false, sendVideoRealtime }
    video = { videoWidth: 640, videoHeight: 480 }
  })

  afterEach(() => {
    vi.useRealTimers()
    getContextSpy.mockRestore()
    toDataURLSpy.mockRestore()
  })

  function makeStreamer() {
    return new VideoFrameStreamer(
      session as unknown as LiveSession,
      video as unknown as HTMLVideoElement,
    )
  }

  it('sends far fewer frames than ticks for a static scene (keyframe interval only)', () => {
    const streamer = makeStreamer()
    streamer.start()

    // 20 ticks at 1s each = 20s of a perfectly still scene.
    vi.advanceTimersByTime(20_000)

    expect(sendVideoRealtime).toHaveBeenCalled()
    expect(sendVideoRealtime.mock.calls.length).toBeLessThan(6)
    expect(sendVideoRealtime.mock.calls.length).toBeGreaterThan(0)
  })

  it('sends a frame on the next tick once the scene changes', () => {
    const streamer = makeStreamer()
    streamer.start()

    // First tick always sends (no baseline yet). Let a couple of static
    // ticks pass so we're past the initial forced send and not yet due for
    // the periodic keyframe.
    vi.advanceTimersByTime(2_000)
    const countBeforeChange = sendVideoRealtime.mock.calls.length

    pixelData = makePixelBuffer(250) // large luminance jump vs. baseline of 100
    vi.advanceTimersByTime(1_000)

    expect(sendVideoRealtime.mock.calls.length).toBe(countBeforeChange + 1)
  })

  it('stops sending once stop() is called', () => {
    const streamer = makeStreamer()
    streamer.start()
    vi.advanceTimersByTime(1_000) // initial forced send
    const countAfterFirstTick = sendVideoRealtime.mock.calls.length
    expect(countAfterFirstTick).toBeGreaterThan(0)

    streamer.stop()
    pixelData = makePixelBuffer(250) // would otherwise trigger a send
    vi.advanceTimersByTime(10_000)

    expect(sendVideoRealtime.mock.calls.length).toBe(countAfterFirstTick)
  })

  it('sends nothing once the session is closed', () => {
    session.isClosed = true
    const streamer = makeStreamer()
    streamer.start()

    vi.advanceTimersByTime(20_000)

    expect(sendVideoRealtime).not.toHaveBeenCalled()
  })
})
