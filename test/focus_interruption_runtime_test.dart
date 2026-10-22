import 'package:flutter_test/flutter_test.dart';
import 'package:resonate/playback/focus_interruption_runtime.dart';

void main() {
  group('FocusInterruptionRuntime event ownership', () {
    test('a transport-cancelled fade keeps ownership until a newer focus event', () {
      final runtime = FocusInterruptionRuntime();

      final unduckGeneration = runtime.focusEventGeneration;
      expect(runtime.ownsFocusEventGeneration(unduckGeneration), isTrue);

      // A transport action does not mutate focus-event ownership.
      expect(runtime.ownsFocusEventGeneration(unduckGeneration), isTrue);

      runtime.noteFocusEvent();
      expect(runtime.ownsFocusEventGeneration(unduckGeneration), isFalse);
      expect(
        runtime.ownsFocusEventGeneration(runtime.focusEventGeneration),
        isTrue,
      );
    });

    test('each focus event advances generation exactly once', () {
      final runtime = FocusInterruptionRuntime();

      expect(runtime.noteFocusEvent(), 1);
      expect(runtime.noteFocusEvent(), 2);
      expect(runtime.focusEventGeneration, 2);
    });

    test('resume generations invalidate stale auto-resume work', () {
      final runtime = FocusInterruptionRuntime();

      final first = runtime.bumpResumeGeneration();
      expect(runtime.ownsResumeGeneration(first), isTrue);

      final second = runtime.bumpResumeGeneration();
      expect(second, first + 1);
      expect(runtime.ownsResumeGeneration(first), isFalse);
      expect(runtime.ownsResumeGeneration(second), isTrue);
    });

    test('focus-loss auto-resume is allowed through the limit but not after it', () {
      final runtime = FocusInterruptionRuntime();
      final lostAt = DateTime.utc(2026, 1, 1, 12);
      runtime.markFocusLost(lostAt);

      expect(
        runtime.mayAutoResume(lostAt.add(const Duration(minutes: 3))),
        isTrue,
      );
      expect(
        runtime.mayAutoResume(
          lostAt.add(const Duration(minutes: 3, milliseconds: 1)),
        ),
        isFalse,
      );

      runtime.clearFocusLost();
      expect(runtime.focusLostAt, isNull);
      expect(runtime.mayAutoResume(lostAt), isTrue);
    });

    test('duck and deferred-unduck flags transition independently', () {
      final runtime = FocusInterruptionRuntime();

      runtime.markDucked();
      runtime.requestUnduckAfterCrossfade();
      expect(runtime.isDucked, isTrue);
      expect(runtime.unduckPendingAfterCrossfade, isTrue);

      runtime.clearUnduckPending();
      expect(runtime.isDucked, isTrue);
      expect(runtime.unduckPendingAfterCrossfade, isFalse);

      runtime.clearDucked();
      expect(runtime.isDucked, isFalse);
    });

    test('unduck target preserves sleep-timer fade and clamps safely', () {
      final runtime = FocusInterruptionRuntime();

      expect(
        runtime.unduckRestoreGain(preampScale: 0.8, sleepFadeScale: 0.5),
        0.4,
      );
      expect(
        runtime.unduckRestoreGain(preampScale: 1.5, sleepFadeScale: 0.5),
        0.75,
      );
      expect(
        runtime.unduckRestoreGain(preampScale: 0.8, sleepFadeScale: -1),
        0.0,
      );
    });

    test('unduck only finalizes for current focus generation outside a transition', () {
      final runtime = FocusInterruptionRuntime();
      final generation = runtime.noteFocusEvent();

      expect(
        runtime.canFinalizeUnduck(generation, transitionLive: false),
        isTrue,
      );
      expect(
        runtime.canFinalizeUnduck(generation, transitionLive: true),
        isFalse,
      );

      runtime.noteFocusEvent();
      expect(
        runtime.canFinalizeUnduck(generation, transitionLive: false),
        isFalse,
      );
    });
  });
}
