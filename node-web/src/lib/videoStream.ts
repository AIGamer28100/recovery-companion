import type { LiveSession } from 'firebase/ai'

const TICK_MS = 1000
const FRAME_WIDTH = 512
const JPEG_QUALITY = 0.55

/** Below this mean per-pixel delta the scene is treated as unchanged. */
const MOTION_THRESHOLD = 6
/** Send a keyframe at least this often even if nothing moved, so vision stays fresh. */
const KEYFRAME_INTERVAL_MS = 6000
/** Thumbnail size used only for cheap frame-to-frame comparison. */
const DIFF_W = 32
const DIFF_H = 24

/**
 * Streams camera frames into an active Live session.
 *
 * Sending is independent of the session's single `receive()` consumer, so this runs
 * safely alongside `startAudioConversation`, which owns that receive loop.
 *
 * Frames are only sent when the scene actually changes, plus a periodic keyframe.
 * A naive fixed 1 FPS stream piles every frame into the model's context, so a long
 * pause with the camera on leaves it chewing through dozens of near-identical
 * images before it can reply — which shows up as steadily worsening response lag.
 * Motion-gating means a still scene costs almost nothing, while someone actually
 * doing a grounding action still streams at full rate so the model can watch it.
 */
export class VideoFrameStreamer {
  private timer: number | null = null
  private lastKeyframeAt = 0
  private prevThumb: Uint8ClampedArray | null = null
  private readonly canvas = document.createElement('canvas')
  private readonly diffCanvas = document.createElement('canvas')
  private readonly session: LiveSession
  private readonly video: HTMLVideoElement

  constructor(session: LiveSession, video: HTMLVideoElement) {
    this.session = session
    this.video = video
    this.diffCanvas.width = DIFF_W
    this.diffCanvas.height = DIFF_H
  }

  start(): void {
    if (this.timer !== null) return
    this.lastKeyframeAt = 0
    this.prevThumb = null
    this.timer = window.setInterval(() => this.tick(), TICK_MS)
  }

  stop(): void {
    if (this.timer === null) return
    window.clearInterval(this.timer)
    this.timer = null
    this.prevThumb = null
  }

  /** Mean absolute luminance delta against the previous thumbnail. */
  private motionSinceLastFrame(): number {
    const ctx = this.diffCanvas.getContext('2d', { willReadFrequently: true })
    if (!ctx) return Number.POSITIVE_INFINITY

    ctx.drawImage(this.video, 0, 0, DIFF_W, DIFF_H)
    const thumb = ctx.getImageData(0, 0, DIFF_W, DIFF_H).data
    const prev = this.prevThumb
    this.prevThumb = new Uint8ClampedArray(thumb)

    if (!prev) return Number.POSITIVE_INFINITY

    let total = 0
    // Step by 4 to read one channel per pixel — enough signal, a quarter the work.
    for (let i = 0; i < thumb.length; i += 4) {
      total += Math.abs(thumb[i] - prev[i])
    }
    return total / (thumb.length / 4)
  }

  private tick(): void {
    const { videoWidth, videoHeight } = this.video
    if (!videoWidth || !videoHeight || this.session.isClosed) return

    const now = Date.now()
    const dueForKeyframe = now - this.lastKeyframeAt >= KEYFRAME_INTERVAL_MS
    const moved = this.motionSinceLastFrame() >= MOTION_THRESHOLD

    if (!moved && !dueForKeyframe) return
    this.lastKeyframeAt = now

    const scale = FRAME_WIDTH / videoWidth
    this.canvas.width = FRAME_WIDTH
    this.canvas.height = Math.round(videoHeight * scale)

    const ctx = this.canvas.getContext('2d')
    if (!ctx) return
    ctx.drawImage(this.video, 0, 0, this.canvas.width, this.canvas.height)

    const base64 = this.canvas.toDataURL('image/jpeg', JPEG_QUALITY).split(',')[1]
    if (!base64) return

    void this.session
      .sendVideoRealtime({ mimeType: 'image/jpeg', data: base64 })
      .catch((err) => console.warn('Dropped a video frame', err))
  }
}
