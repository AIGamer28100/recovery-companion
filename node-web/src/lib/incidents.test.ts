import { describe, it, expect, vi, afterEach } from 'vitest'
import { captureFrame } from './incidents'

describe('captureFrame', () => {
  let getContextSpy: ReturnType<typeof vi.spyOn>
  let toDataURLSpy: ReturnType<typeof vi.spyOn>

  afterEach(() => {
    getContextSpy?.mockRestore()
    toDataURLSpy?.mockRestore()
  })

  it('returns null when the video has no dimensions', () => {
    const video = { videoWidth: 0, videoHeight: 0 } as HTMLVideoElement
    expect(captureFrame(video)).toBeNull()
  })

  it('returns null when video is null', () => {
    expect(captureFrame(null)).toBeNull()
  })

  it('produces a data URL when the video has dimensions', () => {
    const ctx = { drawImage: vi.fn() }
    getContextSpy = vi
      .spyOn(HTMLCanvasElement.prototype, 'getContext')
      .mockImplementation(() => ctx as unknown as CanvasRenderingContext2D)
    toDataURLSpy = vi
      .spyOn(HTMLCanvasElement.prototype, 'toDataURL')
      .mockReturnValue('data:image/jpeg;base64,ZmFrZQ==')

    const video = { videoWidth: 640, videoHeight: 480 } as HTMLVideoElement
    const result = captureFrame(video)

    expect(result).toBe('data:image/jpeg;base64,ZmFrZQ==')
    expect(ctx.drawImage).toHaveBeenCalled()
    expect(toDataURLSpy).toHaveBeenCalledWith('image/jpeg', 0.45)
  })

  it('returns null when the canvas 2d context is unavailable', () => {
    getContextSpy = vi
      .spyOn(HTMLCanvasElement.prototype, 'getContext')
      .mockImplementation(() => null)
    const video = { videoWidth: 640, videoHeight: 480 } as HTMLVideoElement
    expect(captureFrame(video)).toBeNull()
  })
})
