import 'package:flutter_test/flutter_test.dart';
import 'package:resonate_modes_lab/modes/models/mode_action.dart';
import 'package:resonate_modes_lab/modes/models/resonate_mode.dart';
import 'package:resonate_modes_lab/modes/services/mode_interaction_catalog.dart';
import 'package:resonate_modes_lab/modes/services/mode_interaction_guard.dart';

void main() {
  test('Running requires two fingers for every actionable tap', () {
    final policy = ModeInteractionCatalog.policyFor(ResonateMode.running);

    expect(policy.minimumTapPointers, 2);
    expect(policy.accidentalTapProtection, isTrue);
    expect(policy.largeControls, isTrue);
    expect(policy.reducedControlCount, isTrue);

    for (final action in ModeAction.values) {
      expect(policy.requiresTwoFingerTap(action), isTrue);
    }
  });

  test('Running rejects a single-finger accidental tap', () {
    final guard = ModeInteractionGuard(
      ModeInteractionCatalog.policyFor(ResonateMode.running),
    );

    expect(
      guard.allowTap(
        action: ModeAction.playPause,
        pointerCount: 1,
        duration: const Duration(milliseconds: 120),
      ),
      isFalse,
    );
  });

  test('Running accepts a short two-finger tap', () {
    final guard = ModeInteractionGuard(
      ModeInteractionCatalog.policyFor(ResonateMode.running),
    );

    expect(
      guard.allowTap(
        action: ModeAction.playPause,
        pointerCount: 2,
        duration: const Duration(milliseconds: 180),
      ),
      isTrue,
    );
  });

  test('Running rejects a long press even with two fingers', () {
    final guard = ModeInteractionGuard(
      ModeInteractionCatalog.policyFor(ResonateMode.running),
    );

    expect(
      guard.allowTap(
        action: ModeAction.next,
        pointerCount: 2,
        duration: const Duration(milliseconds: 700),
      ),
      isFalse,
    );
  });

  test('Normal mode keeps ordinary one-finger taps', () {
    final guard = ModeInteractionGuard(
      ModeInteractionCatalog.policyFor(ResonateMode.normal),
    );

    expect(
      guard.allowTap(
        action: ModeAction.playPause,
        pointerCount: 1,
        duration: const Duration(milliseconds: 150),
      ),
      isTrue,
    );
  });
}
