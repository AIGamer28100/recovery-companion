// Mirrors the intent of `src/lib/liveTee.test.ts`: proves the tee forwards
// every message unchanged and in order to its "playback" consumer
// (`receive()`), while ALSO mirroring every message, in order, to a second,
// independent consumer (`messages`) — the two-consumer proof DESIGN.md §3.1
// asks for before anything else in the audio pipeline is built. Uses a fake
// message type, not a real `firebase_ai` type, since `LiveSessionTee` is
// generic and has zero SDK imports.

import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:soter_recovery/features/live_session/data/live_session_tee.dart';

class FakeMessage {
  const FakeMessage(this.seq, this.payload);
  final int seq;
  final String payload;
}

Stream<FakeMessage> _fakeSourceStream(List<FakeMessage> messages) async* {
  for (final m in messages) {
    yield m;
  }
}

void main() {
  late List<FakeMessage> messages;

  setUp(() {
    messages = const [
      FakeMessage(1, 'a'),
      FakeMessage(2, 'b'),
      FakeMessage(3, 'c'),
    ];
  });

  test('forwards every message through unchanged and in order via receive()', () async {
    final tee = LiveSessionTee<FakeMessage>(() => _fakeSourceStream(messages));

    final received = await tee.receive().toList();

    expect(received.length, 3);
    expect(received[0], same(messages[0]));
    expect(received[1], same(messages[1]));
    expect(received[2], same(messages[2]));
  });

  test('mirrors every message to onMessage in the same order', () async {
    final onMessageCalls = <FakeMessage>[];
    final tee = LiveSessionTee<FakeMessage>(
      () => _fakeSourceStream(messages),
      onMessage: onMessageCalls.add,
    );

    await tee.receive().toList();

    expect(onMessageCalls, equals(messages));
  });

  test(
    'two consumers both get every message: receive() (playback) and messages (transcript/tool-call)',
    () async {
      final tee = LiveSessionTee<FakeMessage>(() => _fakeSourceStream(messages));

      final messagesConsumerDone = tee.messages.toList();
      final receiveConsumerDone = tee.receive().toList();

      final results = await Future.wait([receiveConsumerDone, messagesConsumerDone]);
      final fromReceive = results[0];
      final fromMessages = results[1];

      expect(fromReceive, equals(messages));
      expect(fromMessages, equals(messages));
    },
  );

  test('calls the real source function exactly once even if receive() is called twice', () async {
    var callCount = 0;
    Stream<FakeMessage> source() {
      callCount++;
      return _fakeSourceStream(messages);
    }

    final tee = LiveSessionTee<FakeMessage>(source);

    final gen1 = tee.receive();
    final gen2 = tee.receive();
    expect(identical(gen1, gen2), isTrue);

    await gen1.toList();
    expect(callCount, 1);
  });

  test('keeps yielding messages even when onMessage throws', () async {
    final onMessageCalls = <FakeMessage>[];
    final tee = LiveSessionTee<FakeMessage>(
      () => _fakeSourceStream(messages),
      onMessage: (m) {
        onMessageCalls.add(m);
        if (m.seq == 2) throw StateError('handler blew up');
      },
    );

    final received = await tee.receive().toList();

    expect(received, equals(messages));
    expect(onMessageCalls, equals(messages));
  });
}
