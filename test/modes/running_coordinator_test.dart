import 'package:flutter_test/flutter_test.dart';
import 'package:resonate/modes/models/motion_state.dart';
import 'package:resonate/modes/models/running_intent.dart';
import 'package:resonate/modes/models/running_session_state.dart';
import 'package:resonate/modes/services/running_coordinator.dart';

void main() {
  final t0 = DateTime(2026, 1, 1, 12);

  test('start emits lifecycle intent and opens an active session', () {
    final coordinator = RunningCoordinator();
    final intent = coordinator.start(t0);

    expect(intent.type, RunningIntentType.sessionStarted);
    expect(intent.at, t0);
    expect(intent.sessionState, RunningSessionState.active);
  });

  test('sustained stationary movement emits a pause suggestion without pausing session', () {
    final coordinator = RunningCoordinator();
    coordinator.start(t0);

    expect(
      coordinator.ingestMotion(MotionState.moving, t0, isPlaying: true),
      hasLength(1),
    );

    final intents = coordinator.ingestMotion(
      MotionState.stationary,
      t0.add(const Duration(seconds: 15)),
      isPlaying: true,
    );

    expect(intents.map((i) => i.type), [
      RunningIntentType.motionChanged,
      RunningIntentType.suggestPause,
    ]);
    expect(coordinator.state, RunningSessionState.active);
  });

  test('host can explicitly accept the suggested pause as a session pause', () {
    final coordinator = RunningCoordinator();
    coordinator.start(t0);
    coordinator.ingestMotion(MotionState.stationary, t0, isPlaying: true);

    final suggestions = coordinator.ingestMotion(
      MotionState.stationary,
      t0.add(const Duration(seconds: 15)),
      isPlaying: true,
    );
    expect(suggestions.last.type, RunningIntentType.suggestPause);

    final accepted = coordinator.pause(t0.add(const Duration(seconds: 16)));
    expect(accepted.type, RunningIntentType.sessionPaused);
    expect(coordinator.state, RunningSessionState.paused);
  });

  test('explicit user pause prevents automatic resume suggestion', () {
    final coordinator = RunningCoordinator();
    coordinator.start(t0);
    coordinator.ingestMotion(MotionState.stationary, t0, isPlaying: true);
    coordinator.ingestMotion(
      MotionState.stationary,
      t0.add(const Duration(seconds: 15)),
      isPlaying: true,
    );
    coordinator.setUserPaused(true);

    final intents = coordinator.ingestMotion(
      MotionState.moving,
      t0.add(const Duration(seconds: 30)),
      isPlaying: false,
    );

    expect(intents.map((i) => i.type), [RunningIntentType.motionChanged]);
  });

  test('completed session rejects stale motion callbacks', () {
    final coordinator = RunningCoordinator();
    coordinator.start(t0);
    coordinator.complete(t0.add(const Duration(minutes: 30)));

    expect(
      coordinator.ingestMotion(
        MotionState.stationary,
        t0.add(const Duration(minutes: 31)),
        isPlaying: true,
      ),
      isEmpty,
    );
  });

  test('exit emits a clean boundary and rejects later motion', () {
    final coordinator = RunningCoordinator();
    coordinator.start(t0);

    final exit = coordinator.exit(t0.add(const Duration(minutes: 5)));
    expect(exit.type, RunningIntentType.sessionExited);
    expect(exit.sessionState, RunningSessionState.idle);

    expect(
      coordinator.ingestMotion(
        MotionState.moving,
        t0.add(const Duration(minutes: 6)),
        isPlaying: true,
      ),
      isEmpty,
    );
  });

  test('resume suggestion is emitted only after stable movement following automation pause', () {
    final coordinator = RunningCoordinator();
    coordinator.start(t0);
    coordinator.ingestMotion(MotionState.stationary, t0, isPlaying: true);
    final pause = coordinator.ingestMotion(
      MotionState.stationary,
      t0.add(const Duration(seconds: 15)),
      isPlaying: true,
    );
    expect(pause.last.type, RunningIntentType.suggestPause);

    final early = coordinator.ingestMotion(
      MotionState.moving,
      t0.add(const Duration(seconds: 20)),
      isPlaying: false,
    );
    expect(early.map((i) => i.type), [RunningIntentType.motionChanged]);

    final resumed = coordinator.ingestMotion(
      MotionState.moving,
      t0.add(const Duration(seconds: 25)),
      isPlaying: false,
    );
    expect(resumed.last.type, RunningIntentType.suggestResume);
  });
}
