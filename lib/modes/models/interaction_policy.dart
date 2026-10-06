import 'mode_action.dart';
import 'resonate_mode.dart';

/// Interaction contract emitted by Modes.
///
/// This is intentionally separate from PlaybackPolicy: the playback engine
/// owns audio behavior, while the host UI owns touch/gesture enforcement.
class InteractionPolicy {
  final ResonateMode mode;
  final int minimumTapPointers;
  final Duration maximumTapDuration;
  final bool largeControls;
  final bool reducedControlCount;
  final bool accidentalTapProtection;
  final bool allowHorizontalSwipeNavigation;
  final Set<ModeAction> twoFingerOnlyActions;

  const InteractionPolicy({
    required this.mode,
    required this.minimumTapPointers,
    required this.maximumTapDuration,
    required this.largeControls,
    required this.reducedControlCount,
    required this.accidentalTapProtection,
    required this.allowHorizontalSwipeNavigation,
    required this.twoFingerOnlyActions,
  });

  bool requiresTwoFingerTap(ModeAction action) =>
      twoFingerOnlyActions.contains(action);

  bool acceptsTap({
    required ModeAction action,
    required int pointerCount,
    required Duration duration,
  }) {
    if (duration > maximumTapDuration) return false;
    if (!action.isPlaybackAction) return pointerCount >= 1;
    final minimum = requiresTwoFingerTap(action) ? 2 : minimumTapPointers;
    return pointerCount >= minimum;
  }
}
