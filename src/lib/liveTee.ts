import type { LiveSession } from 'firebase/ai'

type ServerMessage = Awaited<ReturnType<ReturnType<LiveSession['receive']>['next']>>['value']

/**
 * `LiveSession.receive()` supports exactly ONE consumer, and
 * `startAudioConversation` claims it to pull audio chunks. Running a second
 * loop for transcripts silently steals chunks from playback and makes the
 * conversation choppy.
 *
 * This wraps a session so the real stream is consumed once and every message is
 * both forwarded to the audio controller untouched and mirrored to `onMessage`,
 * which is how we surface live transcripts without starving playback.
 */
export function teeSession(
  session: LiveSession,
  onMessage: (message: ServerMessage) => void,
): LiveSession {
  let wrapped: AsyncGenerator<ServerMessage> | null = null

  const makeWrapped = async function* (): AsyncGenerator<ServerMessage> {
    for await (const message of session.receive()) {
      try {
        onMessage(message)
      } catch (err) {
        console.warn('Transcript handler threw', err)
      }
      yield message
    }
  }

  return new Proxy(session, {
    get(target, prop, receiver) {
      if (prop === 'receive') {
        return () => {
          wrapped ??= makeWrapped()
          return wrapped
        }
      }
      const value = Reflect.get(target, prop, receiver)
      return typeof value === 'function' ? value.bind(target) : value
    },
  }) as LiveSession
}
