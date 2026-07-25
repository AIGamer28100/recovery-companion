import { useEffect, useState } from 'react'
import { signOut } from 'firebase/auth'
import { auth } from '../lib/firebase'
import {
  listenToPatientEvents,
  listenToPatientAlerts,
  listenToPatientIncidents,
  summarizeEvents,
  eventLabel,
  type PatientEvent,
  type PatientAlert,
  type PatientIncident,
} from '../lib/patientActivity'
import { generatePersonalizedCaregiverScript } from '../lib/gemini'
import { logCaregiverAlert } from '../lib/events'
import type { UserProfile } from '../types'

interface Props {
  uid: string
  profile: UserProfile
  /** Resolved from who nominated this caregiver; null until known. */
  patientUid: string | null
}

export default function CaregiverDashboard({ uid, patientUid }: Props) {
  const [events, setEvents] = useState<PatientEvent[]>([])
  const [alerts, setAlerts] = useState<PatientAlert[]>([])
  const [incidents, setIncidents] = useState<PatientIncident[]>([])
  const [script, setScript] = useState<string | null>(null)
  const [loading, setLoading] = useState(false)

  // All three are live Firestore snapshot listeners — the dashboard updates the
  // moment something happens on the patient's device, with no reload.
  useEffect(() => {
    if (!patientUid) return
    const unsubs = [
      listenToPatientEvents(patientUid, setEvents),
      listenToPatientAlerts(patientUid, setAlerts),
      listenToPatientIncidents(patientUid, setIncidents),
    ]
    return () => unsubs.forEach((u) => u())
  }, [patientUid])

  const escalations = incidents.filter((i) => i.stage === 'escalated')

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

  if (!patientUid) {
    return (
      <div className="flex min-h-screen flex-col items-center justify-center gap-4 bg-void px-6 text-center text-ink">
        <h1 className="font-display text-xl">No linked account yet</h1>
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
          <h1 className="text-xs font-medium tracking-[0.2em] text-ink-muted">CAREGIVER VIEW</h1>
          <button type="button" onClick={() => signOut(auth)} className="min-h-14 text-xs text-ink-muted">
            Sign out
          </button>
        </div>

        {escalations.length > 0 && (
          <div
            className="rounded-2xl border border-red-500/50 bg-red-500/10 p-6"
            role="alert"
            aria-live="assertive"
          >
            <h2 className="mb-1 font-display text-lg text-red-200">Urgent — needs your attention</h2>
            <p className="mb-4 text-xs text-red-200/70">
              Flagged from their camera during a live session, after they were asked to stop.
            </p>
            <ul className="flex flex-col gap-4">
              {escalations.slice(0, 3).map((incident) => (
                <li key={incident.id} className="flex gap-4">
                  {incident.frame && (
                    <img
                      src={incident.frame}
                      alt="Snapshot captured when the incident was flagged"
                      className="h-20 w-28 shrink-0 rounded-lg object-cover"
                    />
                  )}
                  <p className="text-sm leading-relaxed text-ink">{incident.observation}</p>
                </li>
              ))}
            </ul>
          </div>
        )}

        {alerts.length > 0 && (
          <div className="rounded-2xl border border-line bg-card p-6">
            <h2 className="mb-4 font-display text-lg">Latest alerts</h2>
            <ul className="flex flex-col gap-3">
              {alerts.slice(0, 3).map((alert) => (
                <li key={alert.id} className="text-sm leading-relaxed text-ink-muted">
                  {alert.script}
                </li>
              ))}
            </ul>
          </div>
        )}

        <div className="rounded-2xl border border-line bg-card p-6">
          <h2 className="mb-4 font-display text-lg">Recent activity</h2>
          {events.length === 0 && <p className="text-sm text-ink-muted">Nothing logged yet.</p>}
          <ul className="flex flex-col gap-2">
            {events.slice(0, 8).map((e) => (
              <li key={e.id} className="flex items-center justify-between text-sm">
                <span className="text-ink">{eventLabel(e.type)}</span>
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
