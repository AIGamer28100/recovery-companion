/**
 * Voice-activity tuning for the Live session.
 *
 * The Live API decides when your turn has ended using server-side VAD. Its
 * defaults are tuned for brisk back-and-forth, which is wrong here: someone in
 * distress speaks in fragments with long thinking pauses, and the default
 * end-of-speech threshold treats those pauses as "they're done" and cuts in.
 *
 * `@firebase/ai` does not surface `realtimeInputConfig` in `LiveModelParams`, and
 * the setup frame is assembled and sent inside `connect()`. So we briefly wrap
 * `WebSocket.prototype.send`, inject the config into the outbound setup frame,
 * and restore the original immediately afterwards. Narrow and reversible, but it
 * IS a workaround — if the SDK later exposes `realtimeInputConfig`, delete this
 * file and pass the config directly.
 */

export const REALTIME_INPUT_CONFIG = {
  automaticActivityDetection: {
    // Default is a few hundred ms. Just over a second lets someone say
    // "umm… I don't… " and keep going without the model stealing the turn.
    silenceDurationMs: 1400,
    // Keep the audio just before speech is detected, so a soft "umm" or a quiet
    // first syllable isn't clipped off the front of the turn.
    prefixPaddingMs: 400,
    // Least eager to declare the turn finished.
    endOfSpeechSensitivity: 'END_SENSITIVITY_LOW',
    // Don't treat every small noise or breath as the start of a new turn.
    startOfSpeechSensitivity: 'START_SENSITIVITY_LOW',
  },
}

/**
 * Runs `connect` with the VAD config injected into the Live setup frame.
 */
export async function connectWithVadConfig<T>(connect: () => Promise<T>): Promise<T> {
  if (typeof WebSocket === 'undefined') return connect()

  const originalSend = WebSocket.prototype.send
  let patched = false

  WebSocket.prototype.send = function (this: WebSocket, data: Parameters<WebSocket['send']>[0]) {
    if (!patched && typeof data === 'string' && data.includes('"setup"')) {
      try {
        const parsed = JSON.parse(data)
        if (parsed?.setup && !parsed.setup.realtimeInputConfig) {
          parsed.setup.realtimeInputConfig = REALTIME_INPUT_CONFIG
          patched = true
          return originalSend.call(this, JSON.stringify(parsed))
        }
      } catch {
        // Not the frame we're looking for — fall through and send it untouched.
      }
    }
    return originalSend.call(this, data)
  }

  try {
    return await connect()
  } finally {
    WebSocket.prototype.send = originalSend
  }
}
