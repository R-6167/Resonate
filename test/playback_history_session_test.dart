import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:resonate/models/listening_event.dart';
import 'package:resonate/playback/playback_history_session.dart';

void main() {
  group('PlaybackHistorySession', () {
    test('stores the active event and updates position ticks', () {
      final session = PlaybackHistorySession();
      final startedAt = DateTime(2026, 1, 2);
      final event = ListeningEvent(
        id: 'event-1',
        songId: 'song-1',
        startedAt: startedAt,
        durationPlayedMs: 0,
        songDurationMs: 180000,
        completionRatio: 0,
        completed: false,
        skipped: false,
      );

      session.activeEvent = event;
      session.updatePosition(42000);

      expect(session.activeEvent, same(event));
      expect(session.positionMs, 42000);

      session.clear();
      expect(session.activeEvent, isNull);
      expect(session.positionMs, 0);
    });

    test('serializes mutations in submission order', () async {
      final session = PlaybackHistorySession();
      final order = <String>[];
      final firstGate = Completer<void>();

      final first = session.enqueue(() async {
        order.add('first-start');
        await firstGate.future;
        order.add('first-end');
      });
      final second = session.enqueue(() async {
        order.add('second');
      });

      await Future<void>.delayed(Duration.zero);
      expect(order, ['first-start']);
      expect(session.operationActive, isTrue);

      firstGate.complete();
      await Future.wait([first, second]);

      expect(order, ['first-start', 'first-end', 'second']);
      expect(session.operationActive, isFalse);
    });

    test('a failed mutation does not poison later queued mutations', () async {
      final session = PlaybackHistorySession();
      final order = <String>[];

      final failed = session.enqueue(() async {
        order.add('failed');
        throw StateError('expected test failure');
      });
      final following = session.enqueue(() async {
        order.add('following');
      });

      await expectLater(failed, throwsA(isA<StateError>()));
      await following;

      expect(order, ['failed', 'following']);
      expect(session.operationActive, isFalse);
    });
  });
}
