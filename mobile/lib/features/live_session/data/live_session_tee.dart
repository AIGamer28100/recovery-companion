import 'dart:async';
import 'dart:developer' as developer;

/// Dart equivalent of `teeSession` in `src/lib/liveTee.ts`.
///
/// **Verified against the installed `firebase_ai: ^3.14.1` source**
/// (`live_session.dart`): `LiveSession.receive()` is backed by a *broadcast*
/// `StreamController`, so — unlike the web SDK, where a second `receive()`
/// call silently steals chunks from the first — calling it twice in Dart
/// would not literally starve either caller, as long as both start listening
/// before the messages they care about arrive (broadcast streams do not
/// replay to late subscribers, and offer no back-pressure).
///
/// This wrapper is still built anyway, per DESIGN.md §3.1's explicit
/// instruction to build it "regardless": it (a) guards against that broadcast
/// implementation detail changing in a future SDK version — exactly the
/// silent-failure class this wrapper defends against on the web side, (b)
/// guarantees no dropped messages regardless of when the transcript/tool-call
/// consumer starts listening relative to session start, since [messages] is
/// fed by the one loop that starts driving as soon as [receive] is first
/// consumed, and (c) keeps exactly one real consumer of the underlying
/// stream, matching the layering rule that only one place in the app is
/// allowed to drive playback.
///
/// [T] is left generic (rather than hard-coded to a `firebase_ai` type) so
/// this file has zero SDK imports and its test can use a plain fake message
/// type, mirroring `liveTee.test.ts`.
class LiveSessionTee<T> {
  LiveSessionTee(this._sourceReceive, {void Function(T message)? onMessage})
      : _onMessage = onMessage;

  /// The real, single-consumer-only receive function being wrapped —
  /// typically `session.receive`.
  final Stream<T> Function() _sourceReceive;
  final void Function(T message)? _onMessage;

  final StreamController<T> _mirror = StreamController<T>.broadcast();
  Stream<T>? _driven;

  /// Returns the stream the playback pipeline should consume. Returns the
  /// SAME stream on every call — the underlying `_sourceReceive()` is only
  /// ever invoked once, the first time this stream is listened to.
  Stream<T> receive() => _driven ??= _drive();

  /// Every message that flows through [receive], mirrored here for any
  /// number of secondary consumers (the transcript UI, the tool-call
  /// handler) — this is the "single internal loop... mirrors every message
  /// to a `Stream<ServerMessage>`" behavior DESIGN.md §3.1 calls for.
  /// Broadcast, so multiple listeners are fine; subscribe before starting
  /// consumption of [receive] to avoid missing early messages.
  Stream<T> get messages => _mirror.stream;

  Stream<T> _drive() async* {
    await for (final message in _sourceReceive()) {
      try {
        _onMessage?.call(message);
      } catch (err, st) {
        // A misbehaving handler must never take playback down with it —
        // mirrors liveTee.ts's `console.warn` catch.
        developer.log(
          'LiveSessionTee: onMessage handler threw',
          error: err,
          stackTrace: st,
        );
      }
      if (!_mirror.isClosed) _mirror.add(message);
      yield message;
    }
    if (!_mirror.isClosed) await _mirror.close();
  }
}
