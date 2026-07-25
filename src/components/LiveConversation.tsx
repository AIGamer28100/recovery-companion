import { useRef, useState } from 'react'
import { startAudioConversation } from 'firebase/ai'
import type { AudioConversationController, LiveSession } from 'firebase/ai'
import { createLiveModel } from '../lib/geminiLive'
import { logEvent } from '../lib/events'

type Status = 'idle' | 'connecting' | 'active' | 'error'

interface Props {
  uid: string
}

export default function LiveConversation({ uid }: Props) {
  const [status, setStatus] = useState<Status>('idle')
  const sessionRef = useRef<LiveSession | null>(null)
  const controllerRef = useRef<AudioConversationController | null>(null)

  const start = async () => {
    setStatus('connecting')
    try {
      const model = createLiveModel()
      const session = await model.connect()
      sessionRef.current = session

      // NOTE: startAudioConversation runs its own receive() loop internally to
      // pull audio chunks. LiveSession.receive() supports exactly ONE consumer —
      // adding a second loop here (e.g. to surface transcripts) silently steals
      // audio chunks from playback and makes the conversation choppy. Leave it
      // as the sole consumer.
      const controller = await startAudioConversation(session)
      controllerRef.current = controller

      setStatus('active')
      logEvent(uid, { type: 'live_conversation', mood: null })
    } catch (err) {
      console.error('Live conversation failed to start', err)
      setStatus('error')
      await cleanup()
    }
  }

  const cleanup = async () => {
    try {
      await controllerRef.current?.stop()
      await sessionRef.current?.close()
    } catch {
      // already torn down
    }
    controllerRef.current = null
    sessionRef.current = null
  }

  const stop = async () => {
    await cleanup()
    setStatus('idle')
  }

  if (status === 'idle' || status === 'error') {
    return (
      <div className="flex flex-col gap-2">
        <button
          type="button"
          onClick={start}
          className="min-h-14 w-full rounded-xl border border-ember/40 bg-ember-soft text-sm font-medium text-ink transition hover:border-ember active:scale-[0.98]"
        >
          🎙️ Talk it through, out loud
        </button>
        {status === 'error' && (
          <p className="text-xs text-ink-muted">
            Couldn&apos;t start the live conversation — allow microphone access and try again.
          </p>
        )}
      </div>
    )
  }

  return (
    <div className="flex flex-col gap-4 rounded-2xl border border-ember/40 bg-card p-6">
      <div className="flex items-center justify-between">
        <span className="flex items-center gap-2 text-xs font-medium tracking-[0.2em] text-ember">
          <span className="h-1.5 w-1.5 animate-pulse rounded-full bg-ember" aria-hidden="true" />
          {status === 'connecting' ? 'CONNECTING' : 'LISTENING'}
        </span>
        <button
          type="button"
          onClick={stop}
          className="min-h-14 rounded-full border border-line px-4 text-xs text-ink-muted transition hover:text-ink"
        >
          End conversation
        </button>
      </div>

      {/* Live voice is a two-way audio channel — this is the visual stand-in for
          a conversation that's happening entirely out loud. */}
      <div className="flex items-end justify-center gap-1.5 py-2" aria-hidden="true">
        {[0, 1, 2, 3, 4, 5, 6].map((i) => (
          <span
            key={i}
            className="w-1.5 rounded-full bg-ember/70"
            style={{
              height: '2rem',
              animation: `voice-bar 1.1s ease-in-out ${i * 0.12}s infinite`,
            }}
          />
        ))}
      </div>
      <style>{`
        @keyframes voice-bar {
          0%, 100% { transform: scaleY(0.25); opacity: 0.5; }
          50% { transform: scaleY(1); opacity: 1; }
        }
        @media (prefers-reduced-motion: reduce) {
          [style*="voice-bar"] { animation: none !important; transform: scaleY(0.6); }
        }
      `}</style>

      <p className="text-center text-sm text-ink-muted" role="status">
        {status === 'connecting'
          ? 'Opening the line…'
          : "Just talk — I'm listening, and you can cut in any time."}
      </p>
    </div>
  )
}
