import { useRef, useState } from 'react'
import { startAudioConversation } from 'firebase/ai'
import type { AudioConversationController, LiveSession } from 'firebase/ai'
import { createLiveModel } from '../lib/geminiLive'
import { logEvent } from '../lib/events'

type Status = 'idle' | 'connecting' | 'active' | 'error'

interface TranscriptLine {
  role: 'user' | 'model'
  text: string
}

interface Props {
  uid: string
}

export default function LiveConversation({ uid }: Props) {
  const [status, setStatus] = useState<Status>('idle')
  const [lines, setLines] = useState<TranscriptLine[]>([])
  const sessionRef = useRef<LiveSession | null>(null)
  const controllerRef = useRef<AudioConversationController | null>(null)

  const appendTranscript = (role: TranscriptLine['role'], chunk: string) => {
    setLines((prev) => {
      const last = prev[prev.length - 1]
      if (last && last.role === role) {
        return [...prev.slice(0, -1), { role, text: last.text + chunk }]
      }
      return [...prev, { role, text: chunk }]
    })
  }

  const listenForTranscripts = async (session: LiveSession) => {
    try {
      for await (const message of session.receive()) {
        if (message.type !== 'serverContent') continue
        if (message.inputTranscription?.text) {
          appendTranscript('user', message.inputTranscription.text)
        }
        if (message.outputTranscription?.text) {
          appendTranscript('model', message.outputTranscription.text)
        }
      }
    } catch {
      // session closed — normal on stop()
    }
  }

  const start = async () => {
    setStatus('connecting')
    setLines([])
    try {
      const model = createLiveModel()
      const session = await model.connect()
      sessionRef.current = session
      const controller = await startAudioConversation(session)
      controllerRef.current = controller
      setStatus('active')
      logEvent(uid, { type: 'live_conversation', mood: null })
      void listenForTranscripts(session)
    } catch (err) {
      console.error('Live conversation failed to start', err)
      setStatus('error')
    }
  }

  const stop = async () => {
    await controllerRef.current?.stop()
    await sessionRef.current?.close()
    controllerRef.current = null
    sessionRef.current = null
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
            Couldn&apos;t start the live conversation — check mic access and try again.
          </p>
        )}
      </div>
    )
  }

  return (
    <div className="flex flex-col gap-3 rounded-2xl border border-ember/40 bg-card p-5">
      <div className="flex items-center justify-between">
        <span className="flex items-center gap-2 text-xs font-medium tracking-[0.2em] text-ember">
          <span className="h-1.5 w-1.5 animate-pulse rounded-full bg-ember" aria-hidden="true" />
          {status === 'connecting' ? 'CONNECTING' : 'LIVE'}
        </span>
        <button
          type="button"
          onClick={stop}
          className="min-h-14 rounded-full border border-line px-4 text-xs text-ink-muted transition hover:text-ink"
        >
          End conversation
        </button>
      </div>
      <div className="flex max-h-56 flex-col gap-2 overflow-y-auto" aria-live="polite">
        {lines.length === 0 && (
          <p className="text-sm text-ink-muted">Say what&apos;s going on — I&apos;m listening.</p>
        )}
        {lines.map((line, i) => (
          <p
            key={i}
            className={`text-sm leading-relaxed ${line.role === 'model' ? 'font-display text-[16px] text-ink' : 'text-ink-muted'}`}
          >
            {line.role === 'user' ? 'You: ' : ''}
            {line.text}
          </p>
        ))}
      </div>
    </div>
  )
}
