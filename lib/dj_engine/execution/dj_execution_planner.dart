import '../core/dj_types.dart';
import '../intelligence/dj_risk_engine.dart';

/// Converts a musical decision into an engine-neutral timeline.
///
/// The Resonate adapter will later map these actions to Audio Engine A/B.
/// No actual playback is performed here.
class DjExecutionPlanner {
  final DjRiskEngine riskEngine;

  const DjExecutionPlanner({this.riskEngine = const DjRiskEngine()});

  DjExecutionPlan plan({
    required DjTrackProfile outgoing,
    required DjTrackProfile incoming,
    required DjTransitionCandidate candidate,
  }) {
    final risks = riskEngine.evaluate(
      outgoing: outgoing,
      incoming: incoming,
      candidate: candidate,
    );
    final severity = riskEngine.severity(risks);

    if (severity >= 0.92) {
      return DjExecutionPlan(
        candidate: candidate,
        fallback: true,
        reason: 'risk_too_high',
        steps: const [],
      );
    }

    final bassDuck = risks.contains(DjRiskType.bassCollision);
    final longerFade = risks.contains(DjRiskType.energyShock);
    final sfxTriggerMs = (candidate.durationMs * 0.35).round().clamp(250, 2200).toInt();
    final steps = <DjExecutionStep>[
      DjExecutionStep(action: 'prepare_incoming', atMs: 0, parameters: {
        'seekMs': candidate.incomingStartMs,
      }),
      DjExecutionStep(action: 'start_incoming', atMs: 0),
      if (longerFade)
        DjExecutionStep(action: 'extend_crossfade', atMs: 0, parameters: {
          'durationMs': (candidate.durationMs * 1.25).round().clamp(2500, 20000),
        }),
      if (bassDuck)
        DjExecutionStep(action: 'duck_incoming_bass', atMs: 0, parameters: {
          'amount': 0.35,
          'durationMs': candidate.durationMs ~/ 2,
        }),
      DjExecutionStep(action: 'phrase_align', atMs: 0, parameters: {
        'kind': candidate.kind.name,
      }),
      DjExecutionStep(action: 'trigger_sfx', atMs: sfxTriggerMs, parameters: {
        'kind': candidate.kind.name,
      }),
      DjExecutionStep(action: 'complete_transition', atMs: candidate.durationMs),
    ];

    return DjExecutionPlan(
      candidate: candidate,
      steps: steps,
      reason: 'planned',
    );
  }
}
