// Verifies `describeCameraForModel` and the director-note builders match
// the web's `cameraAvailability.ts`/`useLiveSession.ts` wording exactly —
// this text is read by the model, not a person, so an exact-string test is
// the right level of rigor (paraphrasing it would be a silent behavior
// change the model would react to differently).

import 'package:flutter_test/flutter_test.dart';
import 'package:soter_recovery/features/live_session/domain/camera_availability.dart';

void main() {
  group('describeCameraForModel', () {
    test('camera on overrides availability state entirely', () {
      expect(
        describeCameraForModel(const CameraAvailability(state: CameraState.blocked, canOffer: false), true),
        'Their camera is currently ON — you can see them. Use it to coach and validate what they do.',
      );
    });

    test('available + off tells the model it may offer the camera once', () {
      final text = describeCameraForModel(
        const CameraAvailability(state: CameraState.available, canOffer: true),
        false,
      );
      expect(text, contains('a working camera IS available'));
      expect(text, contains('ask them'));
    });

    test('blocked tells the model to never ask', () {
      final text = describeCameraForModel(
        const CameraAvailability(state: CameraState.blocked, canOffer: false),
        false,
      );
      expect(text, contains('BLOCKED'));
      expect(text, contains('Do NOT ask'));
    });

    test('none tells the model there is no hardware at all', () {
      final text =
          describeCameraForModel(const CameraAvailability(state: CameraState.none, canOffer: false), false);
      expect(text, contains('NO camera at all'));
    });

    test('unsupported is conservative: never ask', () {
      final text = describeCameraForModel(CameraAvailability.unsupported, false);
      expect(text, contains('unknown'));
      expect(text, contains('Do not ask'));
    });
  });

  group('director notes', () {
    const available = CameraAvailability(state: CameraState.available, canOffer: true);

    test('camera-off note matches the exact useLiveSession.ts wording', () {
      expect(
        cameraOffDirectorNote(available),
        '[Silent director note, not from the user. Their camera is now OFF — you can no longer '
        'see them. Do not comment on it. Keep coaching by voice alone. '
        'Their camera is currently OFF, but a working camera IS available and there is a camera '
        'button on their screen. If you want to coach them through something physical, ask them '
        'once to turn it on and say why it helps.]',
      );
    });

    test('camera-on note matches the exact useLiveSession.ts wording', () {
      expect(
        cameraOnDirectorNote(available),
        '[Silent director note, not from the user. Their camera is currently ON — you can see them. '
        'Use it to coach and validate what they do. '
        'Do not announce this or thank them; just start using it. Say nothing right now unless '
        'you were mid-exercise with them.]',
      );
    });

    test('thermal-degrade note never blames the person and explains why', () {
      final note = cameraThermalDegradeDirectorNote();
      expect(note, contains('overheating'));
      expect(note, contains('not their choice'));
      expect(note, contains('Silent director note'));
    });
  });
}
