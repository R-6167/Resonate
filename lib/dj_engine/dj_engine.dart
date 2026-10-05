export 'core/dj_types.dart';
export 'intelligence/dj_transition_brain.dart';
export 'intelligence/dj_risk_engine.dart';
export 'execution/dj_execution_planner.dart';

import 'core/dj_types.dart';
import 'intelligence/dj_transition_brain.dart';
import 'execution/dj_execution_planner.dart';

/// Public facade for the new DJ intelligence core.
class DjEngine {
  final DjTransitionBrain brain;
  final DjExecutionPlanner execution;

  const DjEngine({
    this.brain = const DjTransitionBrain(),
    this.execution = const DjExecutionPlanner(),
  });

  DjExecutionPlan planTransition({
    required DjTrackProfile outgoing,
    required DjTrackProfile incoming,
    required int outgoingPositionMs,
    int preferredDurationMs = 8000,
    int maxDurationMs = 16000,
  }) {
    final candidate = brain.choose(
      outgoing: outgoing,
      incoming: incoming,
      outgoingPositionMs: outgoingPositionMs,
      preferredDurationMs: preferredDurationMs,
      maxDurationMs: maxDurationMs,
    );
    return execution.plan(
      outgoing: outgoing,
      incoming: incoming,
      candidate: candidate,
    );
  }
}
