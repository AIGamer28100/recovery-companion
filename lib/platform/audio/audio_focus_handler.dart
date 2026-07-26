import 'dart:async';

import 'package:audio_session/audio_session.dart';

/// The only file that imports `audio_session`. Wraps audio-focus and
/// "becoming noisy" handling per DESIGN.md §3.7.
enum FocusSignal {
  /// Permanent loss (an actual phone call took focus, or another app
  /// requested exclusive audio). Caller should pause immediately and start
  /// the grace-window timer described in §3.7.
  lostPermanently,

  /// Transient loss (e.g. a notification sound). Caller should pause and
  /// expects a `resumed` signal shortly — no grace-window/close logic
  /// needed.
  lostTransient,

  /// Focus regained after a transient or permanent loss.
  resumed,

  /// Headphones/BT audio device disconnected mid-call
  /// (`ACTION_AUDIO_BECOMING_NOISY`). Caller should pause playback
  /// immediately so the conversation doesn't suddenly blast out the
  /// speaker.
  becomingNoisy,
}

class AudioFocusHandler {
  StreamSubscription<AudioInterruptionEvent>? _interruptionSub;
  StreamSubscription<void>? _noisySub;
  final StreamController<FocusSignal> _signals =
      StreamController<FocusSignal>.broadcast();

  Stream<FocusSignal> get signals => _signals.stream;

  /// Configures the shared [AudioSession] for a communication-mode call
  /// (paired with the mic's `voiceCommunication` source and the platform
  /// channel's `AudioTrack` attributes — see DESIGN.md §3.4) and starts
  /// listening for focus/noisy events.
  Future<void> start() async {
    final session = await AudioSession.instance;
    await session.configure(
      const AudioSessionConfiguration(
        androidAudioAttributes: AndroidAudioAttributes(
          usage: AndroidAudioUsage.voiceCommunication,
          contentType: AndroidAudioContentType.speech,
        ),
        androidAudioFocusGainType: AndroidAudioFocusGainType.gain,
        androidWillPauseWhenDucked: false,
      ),
    );
    await session.setActive(true);

    _interruptionSub = session.interruptionEventStream.listen((event) {
      if (!event.begin) {
        _signals.add(FocusSignal.resumed);
        return;
      }
      switch (event.type) {
        case AudioInterruptionType.unknown:
          _signals.add(FocusSignal.lostPermanently);
        case AudioInterruptionType.pause:
        case AudioInterruptionType.duck:
          _signals.add(FocusSignal.lostTransient);
      }
    });

    _noisySub = session.becomingNoisyEventStream.listen((_) {
      _signals.add(FocusSignal.becomingNoisy);
    });
  }

  Future<void> stop() async {
    await _interruptionSub?.cancel();
    _interruptionSub = null;
    await _noisySub?.cancel();
    _noisySub = null;
    try {
      final session = await AudioSession.instance;
      await session.setActive(false);
    } catch (_) {
      // Best-effort — nothing more we can do if the platform session is
      // already gone.
    }
  }

  Future<void> dispose() async {
    await stop();
    await _signals.close();
  }
}
