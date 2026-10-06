import 'package:flutter_test/flutter_test.dart';

import '../../lib/modes/models/podcast_intent.dart';
import '../../lib/modes/services/podcast_coordinator.dart';

void main() {
  group('PodcastCoordinator', () {
    final t0 = DateTime(2026, 10, 6, 10);

    test('starts once and requests precise resume when supplied', () {
      final c = PodcastCoordinator();
      final intents = c.start(t0, resumePosition: const Duration(minutes: 12));

      expect(c.isActive, isTrue);
      expect(intents.map((i) => i.type), contains(PodcastIntentType.sessionStarted));
      expect(
        intents.singleWhere((i) => i.type == PodcastIntentType.resumePositionRequired).position,
        const Duration(minutes: 12),
      );
      expect(intents.map((i) => i.type), contains(PodcastIntentType.speedControlsElevated));
      expect(c.start(t0).isEmpty, isTrue);
    });

    test('pause and resume retain precise position', () {
      final c = PodcastCoordinator()..start(t0);

      final paused = c.pause(
        t0.add(const Duration(minutes: 20)),
        position: const Duration(minutes: 20),
      ).single;
      expect(paused.position, const Duration(minutes: 20));

      final resumed = c.resume(
        t0.add(const Duration(minutes: 30)),
      ).single;
      expect(resumed.position, const Duration(minutes: 20));
      expect(c.isPaused, isFalse);
    });

    test('position updates are state-only and reject invalid values', () {
      final c = PodcastCoordinator()..start(t0);

      expect(c.updatePosition(const Duration(minutes: 5)), isEmpty);
      expect(c.lastKnownPosition, const Duration(minutes: 5));
      expect(c.updatePosition(const Duration(seconds: -1)), isEmpty);
      expect(c.lastKnownPosition, const Duration(minutes: 5));
    });

    test('completion and exit create explicit boundaries', () {
      final c = PodcastCoordinator()..start(t0);

      expect(
        c.complete(t0.add(const Duration(hours: 1))).single.type,
        PodcastIntentType.sessionCompleted,
      );
      expect(c.exit(t0).isEmpty, isTrue);

      c.start(t0);
      expect(
        c.exit(t0.add(const Duration(minutes: 2))).single.type,
        PodcastIntentType.sessionExited,
      );
    });

    test('does not control playback or chapters', () {
      final c = PodcastCoordinator();
      expect(c.isActive, isFalse);
      expect(c.lastKnownPosition, isNull);
    });
  });
}
