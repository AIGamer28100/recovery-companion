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

export interface PatientAlert {
  id: string
  script: string
  triggeredBy: string
  createdAt: unknown
}

export interface PatientIncident {
  id: string
  stage: 'intervening' | 'escalated'
  observation: string
  frame?: string
  createdAt: unknown
}

/** Live stream of caregiver-facing alerts, newest first. */
export function listenToPatientAlerts(
  patientUid: string,
  onChange: (alerts: PatientAlert[]) => void,
): () => void {
  const q = query(
    collection(db, 'users', patientUid, 'alerts'),
    orderBy('createdAt', 'desc'),
    limit(10),
  )
  return onSnapshot(q, (snap) => {
    onChange(snap.docs.map((d) => ({ id: d.id, ...(d.data() as Omit<PatientAlert, 'id'>) })))
  })
}

/** Live stream of relapse-risk incidents, newest first. */
export function listenToPatientIncidents(
  patientUid: string,
  onChange: (incidents: PatientIncident[]) => void,
): () => void {
  const q = query(
    collection(db, 'users', patientUid, 'incidents'),
    orderBy('createdAt', 'desc'),
    limit(10),
  )
  return onSnapshot(q, (snap) => {
    onChange(snap.docs.map((d) => ({ id: d.id, ...(d.data() as Omit<PatientIncident, 'id'>) })))
  })
}

/**
 * Single source of truth for how an event type reads to a human.
 *
 * Stored lower-case because these appear mid-sentence in AI prompt summaries;
 * use `eventLabel()` for UI, which capitalises for standalone display.
 */
export const EVENT_LABELS: Record<string, string> = {
  physical_tension: 'physical tension',
  sensory_overload: 'sensory overload',
  craving_spike: 'craving spike',
  elevated_stress: 'proactive stress alert',
  checkin: 'mood check-in',
  reset: 'emergency reset',
  live_conversation: 'live voice conversation',
}

/** Capitalised label for standalone UI display; falls back to the raw type. */
export function eventLabel(type: string): string {
  const label = EVENT_LABELS[type] ?? type
  return label.charAt(0).toUpperCase() + label.slice(1)
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
    ([type, count]) => `${count} × ${EVENT_LABELS[type] ?? type}`,
  )
  const oldest = events[events.length - 1]?.createdAt
  const window =
    oldest instanceof Timestamp
      ? `in the last ${Math.max(1, Math.round((Date.now() - oldest.toMillis()) / 60000))} minutes`
      : 'recently'

  const noun = events.length === 1 ? 'event' : 'events'
  return (
    `Over the ${events.length} most recent ${noun} ${window}: ${parts.join(', ')}. ` +
    (latestMood ? `Most recently tapped mood: ${latestMood}.` : 'No mood tapped recently.')
  )
}
