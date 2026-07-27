/**
 * M7 general-retention TTL (DESIGN.md §5.2, §5.6.2): every events/alerts/
 * incidents/sessions document is written with an `expiresAt` field so a
 * Firestore TTL policy on that field can sweep it automatically, with no
 * Cloud Function or client needing to be online when it fires.
 *
 * `expiresAt` is computed here from the CLIENT's own clock, not derived from
 * `serverTimestamp()` — that sentinel is unresolved at write-construction
 * time, so "createdAt + 180 days" cannot be computed from it client-side.
 * The matching `isValidExpiresAt()` rule in firestore.rules validates this
 * against the server-resolved `createdAt` with a +/-5 minute tolerance
 * window rather than exact equality, because exact equality was verified
 * (via a Firestore emulator test) to reject writes even under near-zero
 * simulated clock skew — see the comment on `isValidExpiresAt()` for details.
 */
export const RETENTION_DAYS = 180

const RETENTION_MS = RETENTION_DAYS * 24 * 60 * 60 * 1000

/** Returns `now + 180 days`, suitable for the `expiresAt` field on a new doc. */
export function retentionExpiresAt(now: number = Date.now()): Date {
  return new Date(now + RETENTION_MS)
}
