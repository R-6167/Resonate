import 'package:flutter_test/flutter_test.dart';
import 'package:resonate_modes_lab/modes/models/audiobook_intent.dart';
import 'package:resonate_modes_lab/modes/services/audiobook_coordinator.dart';

void main() {
  final t0 = DateTime(2026, 10, 6, 10);
  final t1 = t0.add(const Duration(minutes: 1));
  final position = const Duration(minutes: 12, seconds: 30);

  test('starts once and exposes audiobook controls', () {
    final coordinator = AudiobookCoordinator();

    final intents = coordinator.start(t0);

    expect(
      intents.map((intent) => intent.type),
      [
        AudiobookIntentType.sessionStarted,
        AudiobookIntentType.speedControlsElevated,
        AudiobookIntentType.sleepTimerSuggested,
        AudiobookIntentType.chapterNavigationAvailable,
      ],
    );
    expect(coordinator.start(t1), isEmpty);
  });

  test('requests precise resume when a position is supplied', () {
    final coordinator = AudiobookCoordinator();

    final intents = coordinator.start(t0, resumePosition: position);

    expect(
      intents.last.type,
      AudiobookIntentType.resumePositionRequired,
    );
    expect(intents.last.position, position);
    expect(coordinator.lastKnownPosition, position);
  });

  test('pause and resume carry the latest known position', () {
    final coordinator = AudiobookCoordinator()..start(t0);

    coordinator.updatePosition(position);
    final paused = coordinator.pause(t1);

    expect(paused.single.position, position);
    expect(coordinator.isPaused, isTrue);

    final resumed = coordinator.resume(t1.add(const Duration(minutes: 1)));

    expect(resumed.single.position, position);
    expect(coordinator.isPaused, isFalse);
  });

  test('negative positions are ignored', () {
    final coordinator = AudiobookCoordinator()..start(t0);

    coordinator.updatePosition(const Duration(seconds: -1));
    expect(coordinator.lastKnownPosition, isNull);

    coordinator.pause(t1, position: const Duration(seconds: -2));
    expect(coordinator.lastKnownPosition, isNull);
  });

  test('completion freezes the last position and closes the session', () {
    final coordinator = AudiobookCoordinator()..start(t0);

    coordinator.updatePosition(position);
    final intents = coordinator.complete(t1);

    expect(intents.single.type, AudiobookIntentType.sessionCompleted);
    expect(intents.single.position, position);
    expect(coordinator.isActive, isFalse);
    expect(coordinator.startContentIfStale(), isFalse);
  });

  test('exit is a boundary and stale lifecycle calls are ignored', () {
    final coordinator = AudiobookCoordinator()..start(t0);

    final exited = coordinator.exit(t1, position: position);

    expect(exited.single.type, AudiobookIntentType.sessionExited);
    expect(exited.single.position, position);
    expect(coordinator.isActive, isFalse);
    expect(coordinator.pause(t1), isEmpty);
    expect(coordinator.complete(t1), isEmpty);
  });
}
