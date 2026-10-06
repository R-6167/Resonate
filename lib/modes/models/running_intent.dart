import 'motion_state.dart';
import 'running_session_state.dart';
import '../services/running_motion_decision.dart';

/// Integration-neutral output from Running Mode.
///
/// Intents describe what happened or what the host may consider doing. They
/// never call playback, sensors, or device APIs.
enum RunningIntentType {
  sessionStarted,
  sessionPaused,
  sessionResumed,
  sessionCompleted,
  sessionExited,
  motionChanged,
  suggestPause,
  suggestResume,
}

class RunningIntent {
  final RunningIntentType type;
  final DateTime at;
  final RunningSessionState sessionState;
  final MotionState? motionState;
  final RunningMotionDecision? motionDecision;

  const RunningIntent({
    required this.type,
    required this.at,
    required this.sessionState,
    this.motionState,
    this.motionDecision,
  });

  bool get isAutomationSuggestion =>
      type == RunningIntentType.suggestPause ||
      type == RunningIntentType.suggestResume;

  bool get isSessionLifecycleEvent =>
      type == RunningIntentType.sessionStarted ||
      type == RunningIntentType.sessionPaused ||
      type == RunningIntentType.sessionResumed ||
      type == RunningIntentType.sessionCompleted ||
      type == RunningIntentType.sessionExited;

  @override
  String toString() =>
      'RunningIntent(type: $type, at: $at, sessionState: $sessionState, '
      'motionState: $motionState, motionDecision: $motionDecision)';
}
