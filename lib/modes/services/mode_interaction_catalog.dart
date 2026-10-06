import '../models/interaction_policy.dart';
import '../models/mode_action.dart';
import '../models/resonate_mode.dart';

class ModeInteractionCatalog {
  ModeInteractionCatalog._();

  static InteractionPolicy policyFor(ResonateMode mode) {
    switch (mode) {
      case ResonateMode.running:
        return InteractionPolicy(
          mode: mode,
          minimumTapPointers: 2,
          maximumTapDuration: const Duration(milliseconds: 500),
          largeControls: true,
          reducedControlCount: true,
          accidentalTapProtection: true,
          allowHorizontalSwipeNavigation: false,
          twoFingerOnlyActions: ModeAction.values
              .where((action) => action.isPlaybackAction)
              .toSet(),
        );
      case ResonateMode.driving:
        return InteractionPolicy(
          mode: mode,
          minimumTapPointers: 1,
          maximumTapDuration: const Duration(milliseconds: 500),
          largeControls: true,
          reducedControlCount: true,
          accidentalTapProtection: true,
          allowHorizontalSwipeNavigation: false,
          twoFingerOnlyActions: const {},
        );
      case ResonateMode.normal:
        return InteractionPolicy(
          mode: mode,
          minimumTapPointers: 1,
          maximumTapDuration: const Duration(milliseconds: 600),
          largeControls: false,
          reducedControlCount: false,
          accidentalTapProtection: false,
          allowHorizontalSwipeNavigation: true,
          twoFingerOnlyActions: const {},
        );
      case ResonateMode.work:
      case ResonateMode.podcast:
      case ResonateMode.motivation:
      case ResonateMode.audiobook:
        return InteractionPolicy(
          mode: mode,
          minimumTapPointers: 1,
          maximumTapDuration: const Duration(milliseconds: 600),
          largeControls: false,
          reducedControlCount: true,
          accidentalTapProtection: false,
          allowHorizontalSwipeNavigation: true,
          twoFingerOnlyActions: const {},
        );
    }
  }
}
