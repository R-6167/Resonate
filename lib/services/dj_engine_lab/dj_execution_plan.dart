import 'dj_transition_brain.dart';
import 'dj_track_profile.dart';

/// Engine-neutral timeline consumed later by Resonate's A/B audio engines.
/// The planner never owns playback; it only describes what the engines should do.
class DjExecutionPlan {
  final DjTransitionCandidate candidate;
  final List<DjExecutionStep> steps;
  final double risk;
  final bool allowFallback;

  const DjExecutionPlan({
    required this.candidate,
    required this.steps,
    required this.risk,
    this.allowFallback = true,
  });

  bool get isAggressive => risk >= 0.70;
}

class DjExecutionStep {
  final DjExecutionAction action;
  final int atOutgoingMs;
  final int? incomingMs;
  final double value;

  const DjExecutionStep({
    required this.action,
    required this.atOutgoingMs,
    this.incomingMs,
    this.value = 0,
  });
}

enum DjExecutionAction {
  prepareIncoming,
  seekIncoming,
  tempoMatch,
  waitForPhrase,
  startIncoming,
  duckOutgoingBass,
  blend,
  restoreBass,
  finishOutgoing,
}

class DjExecutionPlanner {
  const DjExecutionPlanner();

  DjExecutionPlan build(
    DjTransitionCandidate candidate,
    DjTrackProfile outgoing,
    DjTrackProfile incoming,
  ) {
    final risk = _risk(outgoing, incoming, candidate);
    final start = candidate.startOutgoingMs ??
        (outgoing.durationMs > 0 ? outgoing.durationMs - 8 * 1000 : 0);
    final incomingMs = candidate.incomingStartMs ?? 0;
    final tempoRatio = outgoing.tempo.bpm > 0 && incoming.tempo.bpm > 0
        ? outgoing.tempo.bpm / incoming.tempo.bpm
        : 1.0;

    return DjExecutionPlan(
      candidate: candidate,
      risk: risk,
      steps: [
        DjExecutionStep(
          action: DjExecutionAction.prepareIncoming,
          atOutgoingMs: start,
        ),
        DjExecutionStep(
          action: DjExecutionAction.seekIncoming,
          atOutgoingMs: start,
          incomingMs: incomingMs,
        ),
        DjExecutionStep(
          action: DjExecutionAction.tempoMatch,
          atOutgoingMs: start,
          value: tempoRatio,
        ),
        DjExecutionStep(
          action: DjExecutionAction.waitForPhrase,
          atOutgoingMs: start,
          incomingMs: incomingMs,
        ),
        DjExecutionStep(
          action: DjExecutionAction.startIncoming,
          atOutgoingMs: start,
          incomingMs: incomingMs,
        ),
        DjExecutionStep(
          action: DjExecutionAction.duckOutgoingBass,
          atOutgoingMs: start,
          value: _bassCollision(outgoing, incoming) ? 0.55 : 0.80,
        ),
        DjExecutionStep(
          action: DjExecutionAction.blend,
          atOutgoingMs: start,
          incomingMs: incomingMs,
        ),
        DjExecutionStep(
          action: DjExecutionAction.restoreBass,
          atOutgoingMs: start + 4000,
          value: 1.0,
        ),
        DjExecutionStep(
          action: DjExecutionAction.finishOutgoing,
          atOutgoingMs: start + 8000,
        ),
      ],
    );
  }

  double _risk(
    DjTrackProfile a,
    DjTrackProfile b,
    DjTransitionCandidate candidate,
  ) {
    var risk = 1.0 - candidate.score;
    if (_bassCollision(a, b)) risk += 0.18;
    if ((a.energy.integrated - b.energy.integrated).abs() > 0.55) {
      risk += 0.16;
    }
    if (a.structure.confidence < 0.40 || b.structure.confidence < 0.40) {
      risk += 0.10;
    }
    return risk.clamp(0.0, 1.0);
  }

  bool _bassCollision(DjTrackProfile a, DjTrackProfile b) {
    return a.spectral.bassRatio > 0.38 && b.spectral.bassRatio > 0.38;
  }
}
