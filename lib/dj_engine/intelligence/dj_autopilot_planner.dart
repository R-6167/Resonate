import '../../services/dj_transition_memory.dart';
import '../core/dj_types.dart';
import 'dj_transition_brain.dart';

/// Local autonomous transition selector.
///
/// The brain proposes musically valid candidates; this layer learns which
/// strategy tends to work for this pair and globally, then softly reranks.
/// Learning can never remove the safe fallback.
class DjAutopilotPlanner {
  final DjTransitionBrain brain;

  const DjAutopilotPlanner({this.brain = const DjTransitionBrain()});

  Future<DjTransitionCandidate> choose({
    required DjTrackProfile outgoing,
    required DjTrackProfile incoming,
    required int outgoingPositionMs,
    int preferredDurationMs = 8000,
    int maxDurationMs = 16000,
  }) async {
    final candidates = brain.generate(
      outgoing: outgoing,
      incoming: incoming,
      outgoingPositionMs: outgoingPositionMs,
      preferredDurationMs: preferredDurationMs,
      maxDurationMs: maxDurationMs,
    );
    if (candidates.isEmpty) {
      return brain.choose(
        outgoing: outgoing,
        incoming: incoming,
        outgoingPositionMs: outgoingPositionMs,
        preferredDurationMs: preferredDurationMs,
        maxDurationMs: maxDurationMs,
      );
    }

    final pair = await DjTransitionMemory.pairStrategySignals(
      outgoing.songId,
      incoming.songId,
    );
    final global = await DjTransitionMemory.strategySignals();

    DjTransitionCandidate best = candidates.first;
    var bestScore = double.negativeInfinity;
    for (final candidate in candidates) {
      final key = candidate.kind.name;
      final pairSignal = pair[key]?.$1 ?? 0.0;
      final pairEvidence = pair[key]?.$2 ?? 0.0;
      final globalSignal = global[key]?.$1 ?? 0.0;
      final globalEvidence = global[key]?.$2 ?? 0.0;

      // Pair evidence is strongest; global evidence only breaks weakly.
      final learning = pairSignal * (0.24 * pairEvidence.clamp(0.0, 1.0)) +
          globalSignal * (0.08 * globalEvidence.clamp(0.0, 1.0));
      // Never let learning overpower the musical/risk score.
      final adjusted = candidate.score + learning.clamp(-0.24, 0.24);
      if (adjusted > bestScore) {
        bestScore = adjusted;
        best = candidate;
      }
    }
    return best;
  }
}
