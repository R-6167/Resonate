import 'package:flutter_test/flutter_test.dart';

import '../../lib/modes/models/resonate_mode.dart';
import '../../lib/modes/models/work_intent.dart';
import '../../lib/modes/services/work_coordinator.dart';

void main() {
  group('WorkCoordinator', () {
    final t0 = DateTime(2026, 10, 6, 9);

    test('starts an idle work session once', () {
      final coordinator = WorkCoordinator();

      expect(
        coordinator.start(t0).single.type,
        WorkIntentType.sessionStarted,
      );
      expect(coordinator.isActive, isTrue);
      expect(coordinator.isPaused, isFalse);
      expect(coordinator.start(t0).isEmpty, isTrue);
    });

    test('pause and resume preserve the same work session', () {
      final coordinator = WorkCoordinator()..start(t0);

      expect(
        coordinator.pause(t0.add(const Duration(hours: 1))).single.type,
        WorkIntentType.sessionPaused,
      );
      expect(coordinator.isActive, isTrue);
      expect(coordinator.isPaused, isTrue);

      expect(
        coordinator.resume(t0.add(const Duration(hours: 1, minutes: 15))).single.type,
        WorkIntentType.sessionResumed,
      );
      expect(coordinator.isActive, isTrue);
      expect(coordinator.isPaused, isFalse);
    });

    test('completion closes the session and rejects stale lifecycle calls', () {
      final coordinator = WorkCoordinator()..start(t0);

      expect(
        coordinator.complete(t0.add(const Duration(hours: 2))).single.type,
        WorkIntentType.sessionCompleted,
      );
      expect(coordinator.isActive, isFalse);
      expect(coordinator.pause(t0).isEmpty, isTrue);
      expect(coordinator.resume(t0).isEmpty, isTrue);
      expect(coordinator.complete(t0).isEmpty, isTrue);
    });

    test('exit creates a boundary without reporting completion', () {
      final coordinator = WorkCoordinator()..start(t0);

      final intent = coordinator.exit(t0.add(const Duration(hours: 1))).single;
      expect(intent.type, WorkIntentType.sessionExited);
      expect(coordinator.isActive, isFalse);
      expect(coordinator.exit(t0).isEmpty, isTrue);
    });

    test('mode is carried through intents without controlling playback', () {
      final coordinator = WorkCoordinator()..setMode(ResonateMode.work);

      final intent = coordinator.start(t0).single;
      expect(intent.mode, ResonateMode.work);
    });
  });
}
