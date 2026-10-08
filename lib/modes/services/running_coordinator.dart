import '../models/motion_state.dart';
import '../models/running_intent.dart';
import '../models/running_session_state.dart';
import 'running_motion_decision.dart';
import 'running_session_controller.dart';

/// Composes Running session lifecycle and movement decisions into one
/// deterministic integration stream.
///
/// The coordinator owns Running state only. A host application consumes the
/// returned intents and decides whether to control actual playback.
class RunningCoordinator {
  final RunningSessionController session;
  final RunningMotionDecisionEngine motion;

  RunningCoordinator({
    RunningSessionController? session,
    RunningMotionDecisionEngine? motion,
  })  : session = session ?? RunningSessionController(),
        motion = motion ?? RunningMotionDecisionEngine();

  RunningSessionState get state => session.state;

  RunningIntent start(DateTime now) {
    motion.reset();
    session.start(now);
    return RunningIntent(
      type: RunningIntentType.sessionStarted,
      at: now,
      sessionState: session.state,
    );
  }

  RunningIntent pause(DateTime now) {
    session.pause(now);
    return RunningIntent(
      type: RunningIntentType.sessionPaused,
      at: now,
      sessionState: session.state,
    );
  }

  RunningIntent resume(DateTime now) {
    session.resume(now);
    return RunningIntent(
      type: RunningIntentType.sessionResumed,
      at: now,
      sessionState: session.state,
    );
  }

  RunningIntent complete(DateTime now) {
    session.complete(now);
    motion.reset();
    return RunningIntent(
      type: RunningIntentType.sessionCompleted,
      at: now,
      sessionState: session.state,
    );
  }

  RunningIntent exit(DateTime now) {
    session.exit(now);
    motion.reset();
    return RunningIntent(
      type: RunningIntentType.sessionExited,
      at: now,
      sessionState: session.state,
    );
  }

  /// Reports a sensor-derived state change and, when appropriate, emits an
  /// automation suggestion.
  ///
  /// A completed or idle session ignores movement so stale sensor callbacks
  /// cannot create playback suggestions outside a Running session.
  List<RunningIntent> ingestMotion(
    MotionState state,
    DateTime now, {
    required bool isPlaying,
  }) {
    if (session.state != RunningSessionState.active &&
        session.state != RunningSessionState.paused) {
      return const [];
    }

    final intents = <RunningIntent>[
      RunningIntent(
        type: RunningIntentType.motionChanged,
        at: now,
        sessionState: session.state,
        motionState: state,
        motionDecision: RunningMotionDecision.maintain,
      ),
    ];

    final decision = motion.ingest(state, now, isPlaying: isPlaying);

    if (decision == RunningMotionDecision.suggestPause ||
        decision == RunningMotionDecision.suggestResume) {
      intents.add(
        RunningIntent(
          type: decision == RunningMotionDecision.suggestPause
              ? RunningIntentType.suggestPause
              : RunningIntentType.suggestResume,
          at: now,
          sessionState: session.state,
          motionState: state,
          motionDecision: decision,
        ),
      );
    }

    return intents;
  }

  /// Records whether the user explicitly paused playback. This is deliberately
  /// separate from session.pause(), because playback pause does not necessarily
  /// mean the Running session itself is paused.
  void setUserPaused(bool paused) => motion.setUserPaused(paused);
}
