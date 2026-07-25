import { collection, onSnapshot, orderBy, query, limit, Timestamp } from 'firebase/firestore'
import { db } from './firebase'
import type { AppEvent } from '../types'

export interface PatientEvent extends AppEvent {
  id: string
}

export function listenToPatientEvents(
  patientUid: string,
  onChange: (events: PatientEvent[]) => void,
): () => void {
  const q = query(
    collection(db, 'users', patientUid, 'events'),
    orderBy('createdAt', 'desc'),
    limit(20),
  )
  return onSnapshot(q, (snap) => {
    onChange(snap.docs.map((d) => ({ id: d.id, ...(d.data() as AppEvent) })))
  })
}

const TYPE_LABELS: Record<string, string> = {
  physical_tension: 'physical tension',
  sensory_overload: 'sensory overload',
  craving_spike: 'craving spike',
  elevated_stress: 'proactive stress alert',
  checkin: 'mood check-in',
  reset: 'emergency reset',
  live_conversation: 'live voice conversation',
}

export function summarizeEvents(events: PatientEvent[]): string {
  if (events.length === 0) return 'No activity recorded yet.'

  const counts: Record<string, number> = {}
  let latestMood: string | null = null
  for (const e of events) {
    counts[e.type] = (counts[e.type] ?? 0) + 1
    if (!latestMood && e.mood) latestMood = e.mood
  }

  const parts = Object.entries(counts).map(
    ([type, count]) => `${count} × ${TYPE_LABELS[type] ?? type}`,
  )
  const oldest = events[events.length - 1]?.createdAt
  const window =
    oldest instanceof Timestamp
      ? `in the last ${Math.max(1, Math.round((Date.now() - oldest.toMillis()) / 60000))} minutes`
      : 'recently'

  return (
    `Over the ${events.length} most recent events ${window}: ${parts.join(', ')}. ` +
    (latestMood ? `Most recently tapped mood: ${latestMood}.` : 'No mood tapped recently.')
  )
}
