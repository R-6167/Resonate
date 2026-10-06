import '../core/dj_types.dart';
import '../core/dj_policy.dart';
import '../intelligence/dj_risk_engine.dart';

/// Converts a musical decision into an engine-neutral timeline.
///
/// The Resonate adapter maps these actions to Audio Engine A/B.
/// No actual playback is performed here.
class DjExecutionPlanner {
  final DjRiskEngine riskEngine;

  const DjExecutionPlanner({this.riskEngine = const DjRiskEngine()});

  DjExecutionPlan plan({
    required DjTrackProfile outgoing,
    required DjTrackProfile incoming,
    required DjTransitionCandidate candidate,
    DjPolicy policy = DjPolicy.balanced,
  }) {
    final risks = riskEngine.evaluate(
      outgoing: outgoing,
      incoming: incoming,
      candidate: candidate,
      policy: policy,
    );
    final severity = riskEngine.severity(risks);

    if (severity >= policy.riskSeverityLimit) {
      return DjExecutionPlan(
        candidate: candidate,
        fallback: true,
        reason: 'risk_too_high',
        steps: const [],
      );
    }

    final bassDuck = risks.contains(DjRiskType.bassCollision);
    final longerFade = risks.contains(DjRiskType.energyShock);
    final sfxTriggerMs = _phraseSnappedSfxMs(
      durationMs: candidate.durationMs,
      kind: candidate.kind,
      outgoing: outgoing,
      outgoingExitMs: candidate.outgoingExitMs,
    );
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
        'snapped': true,
      }),
      DjExecutionStep(action: 'complete_transition', atMs: candidate.durationMs),
    ];

    return DjExecutionPlan(
      candidate: candidate,
      steps: steps,
      reason: 'planned',
    );
  }

  /// Prefer a beat/phrase boundary during the crossfade instead of a fixed 35%.
  static int _phraseSnappedSfxMs({
    required int durationMs,
    required DjTransitionKind kind,
    required DjTrackProfile outgoing,
    int? outgoingExitMs,
  }) {
    final dur = durationMs.clamp(500, 20000);
    // Ideal fraction of the fade: earlier for glue, later for drop impact.
    final fraction = switch (kind) {
      DjTransitionKind.safeCrossfade => 0.22,
      DjTransitionKind.energyBridge => 0.28,
      DjTransitionKind.outroIntro => 0.30,
      DjTransitionKind.phraseBlend => 0.40,
      DjTransitionKind.beatBlend => 0.38,
      DjTransitionKind.breakdownDrop => 0.52,
    };
    final ideal = (dur * fraction).round().clamp(180, dur - 120);

    final beats = outgoing.beatGrid.beatMs;
    if (beats.length < 4) return ideal;

    // Approximate where the outgoing track sits when the fade starts.
    final exitHint = outgoingExitMs ??
        (outgoing.durationMs > 0
            ? (outgoing.durationMs - dur).clamp(0, outgoing.durationMs)
            : 0);
    final windowStart = exitHint;
    final windowEnd = exitHint + dur;

    var bestRel = ideal;
    var bestDist = 1 << 30;
    for (final b in beats) {
      if (b < windowStart + 120 || b > windowEnd - 80) continue;
      final rel = b - windowStart;
      final d = (rel - ideal).abs();
      if (d < bestDist) {
        bestDist = d;
        bestRel = rel;
      }
    }

    // Prefer downbeats / 4-beat phrase starts when available.
    final downs = outgoing.beatGrid.downbeatMs;
    if (downs.isNotEmpty) {
      for (final b in downs) {
        if (b < windowStart + 120 || b > windowEnd - 80) continue;
        final rel = b - windowStart;
        final d = (rel - ideal).abs();
        // Prefer downbeat within 180ms of ideal over a plain beat.
        if (d <= bestDist + 180 && d < bestDist + 40) {
          bestDist = d;
          bestRel = rel;
        } else if (d < bestDist) {
          bestDist = d;
          bestRel = rel;
        }
      }
    }

    return bestRel.clamp(150, dur - 100);
  }
}
