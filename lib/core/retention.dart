/// M7 general-retention TTL (DESIGN.md §5.2, §5.6.2): every events/alerts/
/// incidents/sessions document is written with an `expiresAt` field so a
/// Firestore TTL policy on that field can sweep it automatically, with no
/// Cloud Function or client needing to be online when it fires.
///
/// A faithful Dart port of `node-web/src/lib/retention.ts`. `expiresAt` is
/// computed here from the CLIENT's own clock, not derived from
/// `FieldValue.serverTimestamp()` — that sentinel is unresolved at
/// write-construction time, so "createdAt + 180 days" cannot be computed
/// from it client-side. The matching `isValidExpiresAt()` rule in
/// `firestore.rules` validates this against the server-resolved `createdAt`
/// with a +/-5 minute tolerance window rather than exact equality, because
/// exact equality was verified (via a Firestore emulator test) to reject
/// writes even under near-zero simulated clock skew — see the comment on
/// `isValidExpiresAt()` in `firestore.rules` for details.
const int retentionDays = 180;

/// Returns `now + 180 days` (UTC), suitable for the `expiresAt` field on a
/// new document. Pure and testable without Firestore.
DateTime retentionExpiresAt([DateTime? now]) {
  return (now ?? DateTime.now()).toUtc().add(const Duration(days: retentionDays));
}
