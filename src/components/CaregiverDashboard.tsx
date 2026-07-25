import { useEffect, useState } from 'react'
import { signOut } from 'firebase/auth'
import { auth } from '../lib/firebase'
import { listenToPatientEvents, summarizeEvents, type PatientEvent } from '../lib/patientActivity'
import { generatePersonalizedCaregiverScript } from '../lib/gemini'
import { logCaregiverAlert } from '../lib/events'
import type { UserProfile } from '../types'

const TYPE_LABELS: Record<string, string> = {
  physical_tension: 'Physical tension',
  sensory_overload: 'Sensory overload',
  craving_spike: 'Craving spike',
  elevated_stress: 'Proactive stress alert',
  checkin: 'Mood check-in',
  reset: 'Emergency reset',
  live_conversation: 'Live voice conversation',
}

interface Props {
  uid: string
  profile: UserProfile
}

export default function CaregiverDashboard({ uid, profile }: Props) {
  const [events, setEvents] = useState<PatientEvent[]>([])
  const [script, setScript] = useState<string | null>(null)
  const [loading, setLoading] = useState(false)

  useEffect(() => {
    if (!profile.linkedPatientUid) return
    return listenToPatientEvents(profile.linkedPatientUid, setEvents)
  }, [profile.linkedPatientUid])

  const requestScript = async () => {
    setLoading(true)
    setScript(null)
    try {
      const summary = summarizeEvents(events)
      const text = await generatePersonalizedCaregiverScript(summary)
      setScript(text)
      logCaregiverAlert(uid, { script: text, triggeredBy: 'manual' })
    } catch (err) {
      console.error('generatePersonalizedCaregiverScript failed', err)
    } finally {
      setLoading(false)
    }
  }

  if (!profile.linkedPatientUid) {
    return (
      <div className="flex min-h-screen flex-col items-center justify-center gap-4 bg-void px-6 text-center text-ink">
        <p className="font-display text-xl">No linked account yet</p>
        <p className="max-w-sm text-sm text-ink-muted">
          We couldn&apos;t find a patient account with that email when you signed up. Ask them to
          sign in at least once, then reload this page.
        </p>
        <button type="button" onClick={() => signOut(auth)} className="min-h-14 text-xs text-ink-muted">
          Sign out
        </button>
      </div>
    )
  }

  return (
    <div className="min-h-screen bg-void px-5 py-6 text-ink">
      <div className="ember-field" />
      <div className="relative z-10 mx-auto flex max-w-2xl flex-col gap-6">
        <div className="flex items-center justify-between">
          <span className="text-xs font-medium tracking-[0.2em] text-ink-muted">CAREGIVER VIEW</span>
          <button type="button" onClick={() => signOut(auth)} className="min-h-14 text-xs text-ink-muted">
            Sign out
          </button>
        </div>

        <div className="rounded-2xl border border-line bg-card p-6">
          <h2 className="mb-4 font-display text-lg">Recent activity</h2>
          {events.length === 0 && <p className="text-sm text-ink-muted">Nothing logged yet.</p>}
          <ul className="flex flex-col gap-2">
            {events.slice(0, 8).map((e) => (
              <li key={e.id} className="flex items-center justify-between text-sm">
                <span className="text-ink">{TYPE_LABELS[e.type] ?? e.type}</span>
                {e.mood && <span className="text-xs text-ink-muted">{e.mood}</span>}
              </li>
            ))}
          </ul>
        </div>

        <button
          type="button"
          disabled={loading}
          onClick={requestScript}
          className="min-h-14 w-full rounded-xl bg-ink text-sm font-semibold text-void transition active:scale-[0.98] disabled:opacity-40"
        >
          {loading ? 'Thinking…' : 'Get a script based on their recent activity'}
        </button>

        {script && (
          <div className="rounded-2xl border border-ember/40 bg-card p-6" role="log" aria-live="polite">
            <p className="whitespace-pre-wrap font-display text-[17px] leading-relaxed">{script}</p>
          </div>
        )}
      </div>
    </div>
  )
}
