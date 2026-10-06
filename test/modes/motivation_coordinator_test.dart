import 'package:flutter_test/flutter_test.dart';
import 'package:resonate_modes_lab/modes/models/media_type.dart';
import 'package:resonate_modes_lab/modes/models/motivation_intent.dart';
import 'package:resonate_modes_lab/modes/services/motivation_coordinator.dart';

void main() {
  final t0 = DateTime(2026, 10, 6, 10);
  final t1 = t0.add(const Duration(minutes: 1));

  test('starts an idempotent motivation session', () {
    final coordinator = MotivationCoordinator();

    expect(coordinator.start(t0).single.type,
        MotivationIntentType.sessionStarted);
    expect(coordinator.start(t1), isEmpty);
    expect(coordinator.isActive, isTrue);
  });

  test('pause and resume preserve the same session boundary', () {
    final coordinator = MotivationCoordinator()..start(t0);

    expect(coordinator.pause(t1).single.type,
        MotivationIntentType.sessionPaused);
    expect(coordinator.resume(t1).single.type,
        MotivationIntentType.sessionResumed);
    expect(coordinator.isActive, isTrue);
  });

  test('motivation speech completion suggests music follow-up', () {
    final coordinator = MotivationCoordinator()..start(t0);

    final started = coordinator.startContent(MediaType.motivation, t1);
    expect(started.single.type, MotivationIntentType.speechStarted);

    final completed = coordinator.completeContent(
      MediaType.motivation,
      t1.add(const Duration(minutes: 5)),
    );

    expect(
      completed.map((intent) => intent.type),
      [
        MotivationIntentType.speechCompleted,
        MotivationIntentType.musicFollowupSuggested,
      ],
    );
    expect(coordinator.currentMediaType, isNull);
  });

  test('music does not create a speech transition', () {
    final coordinator = MotivationCoordinator()..start(t0);

    expect(
      coordinator.startContent(MediaType.music, t1),
      isEmpty,
    );
    expect(
      coordinator.completeContent(MediaType.music, t1),
      isEmpty,
    );
  });

  test('inactive and stale content events are ignored', () {
    final coordinator = MotivationCoordinator();

    expect(coordinator.startContent(MediaType.motivation, t0), isEmpty);
    expect(coordinator.completeContent(MediaType.motivation, t0), isEmpty);

    coordinator.start(t0);
    coordinator.startContent(MediaType.motivation, t0);
    expect(coordinator.completeContent(MediaType.music, t1), isEmpty);
    expect(coordinator.currentMediaType, MediaType.motivation);
  });

  test('completion and exit close the session and reject stale events', () {
    final coordinator = MotivationCoordinator()..start(t0);

    expect(coordinator.complete(t1).single.type,
        MotivationIntentType.sessionCompleted);
    expect(coordinator.startContent(MediaType.motivation, t1), isEmpty);

    coordinator.start(t1);
    expect(coordinator.exit(t1).single.type,
        MotivationIntentType.sessionExited);
    expect(coordinator.completeContent(MediaType.motivation, t1), isEmpty);
  });
}
