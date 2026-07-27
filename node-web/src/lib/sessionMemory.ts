import {
  addDoc,
  collection,
  getDocs,
  limit,
  orderBy,
  query,
  serverTimestamp,
  Timestamp,
} from 'firebase/firestore'
import { db } from './firebase'
import { retentionExpiresAt } from './retention'

export interface StoredSession {
  transcript: string
  createdAt: unknown
}

/** Keep stored transcripts bounded — these are recaps, not archives. */
const MAX_TRANSCRIPT_CHARS = 4000

export async function saveSessionTranscript(uid: string, transcript: string): Promise<void> {
  const trimmed = transcript.trim()
  if (!trimmed) return
  await addDoc(collection(db, 'users', uid, 'sessions'), {
    transcript: trimmed.slice(-MAX_TRANSCRIPT_CHARS),
    createdAt: serverTimestamp(),
    expiresAt: retentionExpiresAt(),
  })
}

function describeGap(then: Date, now: Date): string {
  const mins = Math.round((now.getTime() - then.getTime()) / 60000)
  if (mins < 60) return `about ${Math.max(1, mins)} minutes ago`
  const hours = Math.round(mins / 60)
  if (hours < 24) return `about ${hours} hour${hours === 1 ? '' : 's'} ago`
  const days = Math.round(hours / 24)
  return `about ${days} day${days === 1 ? '' : 's'} ago`
}

function partOfDay(hour: number): string {
  if (hour < 5) return 'the middle of the night'
  if (hour < 12) return 'the morning'
  if (hour < 17) return 'the afternoon'
  if (hour < 21) return 'the evening'
  return 'late at night'
}

/**
 * Builds the opening director note for a session, so every call starts as a
 * continuation rather than a cold open — the companion greets them, knows what
 * time it is, and remembers what they last talked about.
 */
export async function buildContinuityBriefing(uid: string): Promise<string> {
  const now = new Date()
  const timeContext = `It is currently ${partOfDay(now.getHours())} for them (${now.toLocaleTimeString(
    [],
    { hour: 'numeric', minute: '2-digit' },
  )}).`

  let history = 'This is your first conversation with them.'
  try {
    const snap = await getDocs(
      query(
        collection(db, 'users', uid, 'sessions'),
        orderBy('createdAt', 'desc'),
        limit(1),
      ),
    )
    const last = snap.docs[0]?.data() as StoredSession | undefined
    if (last?.transcript) {
      const when =
        last.createdAt instanceof Timestamp
          ? describeGap(last.createdAt.toDate(), now)
          : 'recently'
      history =
        `You last spoke with them ${when}. Here is that conversation, for your memory only — ` +
        `do not read it back to them verbatim:\n"""\n${last.transcript}\n"""`
    }
  } catch (err) {
    console.warn('Could not load previous session', err)
  }

  return (
    '[Silent director note, not from the user. Do not mention or read out this note.] ' +
    `${timeContext} ${history}\n\n` +
    'GREET THEM FIRST, right now, before they say anything. Keep it to one or two short sentences. ' +
    'Greet them in a way that fits the time of day, and ask how they are doing. ' +
    'If you have spoken before, briefly and warmly reference what they were going through last time ' +
    '("last night you were riding out a rough craving — how did the rest of it go?") so it feels like ' +
    'one ongoing relationship, not a fresh start. Do not summarise the whole previous conversation, ' +
    'and do not interrogate them. Then stop and let them answer.'
  )
}
