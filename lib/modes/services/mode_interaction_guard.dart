import '../models/interaction_policy.dart';
import '../models/mode_action.dart';

/// Pure interaction gate used by the host UI before dispatching an action.
class ModeInteractionGuard {
  final InteractionPolicy policy;

  const ModeInteractionGuard(this.policy);

  /// Running's safe tap path: playback actions require two fingers;
  /// configuration/navigation remains available with one finger.
  bool allowTap({
    required ModeAction action,
    required int pointerCount,
    required Duration duration,
  }) =>
      policy.acceptsTap(
        action: action,
        pointerCount: pointerCount,
        duration: duration,
      );
}
