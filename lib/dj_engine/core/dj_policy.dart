import 'dj_types.dart';

/// How boldly DJ Mode may prefer musical transitions over safe crossfades.
enum DjAggressiveness {
  /// Prefer safe crossfade; stricter confidence and risk gates.
  safe,

  /// Default — balanced musical scoring with existing risk limits.
  balanced,

  /// Prefer phrase/energy transitions when analysis supports them.
  musical,
}

extension DjAggressivenessX on DjAggressiveness {
  String get id => name;

  String get label => switch (this) {
        DjAggressiveness.safe => 'Safe',
        DjAggressiveness.balanced => 'Balanced',
        DjAggressiveness.musical => 'Musical',
      };

  String get subtitle => switch (this) {
        DjAggressiveness.safe =>
          'Mostly gentle crossfades. Fancy blends only when analysis is strong.',
        DjAggressiveness.balanced =>
          'Mix of beat-aligned and musical transitions when confidence allows.',
        DjAggressiveness.musical =>
          'Favour phrase/energy blends. Still falls back if risk is extreme.',
      };

  static DjAggressiveness fromId(String? raw) {
    switch (raw) {
      case 'safe':
        return DjAggressiveness.safe;
      case 'musical':
        return DjAggressiveness.musical;
      default:
        return DjAggressiveness.balanced;
    }
  }
}

/// Tunable policy applied by the transition brain and execution planner.
class DjPolicy {
  final DjAggressiveness aggressiveness;

  /// Minimum candidate confidence (0.20–0.80) before a non-safe plan is used.
  final double minConfidence;

  /// When enabled, harmonic compatibility participates in transition scoring.
  /// Disabled by default to preserve the pre-setting DJ behavior.
  final bool harmonicMix;

  const DjPolicy({
    this.aggressiveness = DjAggressiveness.balanced,
    this.minConfidence = 0.40,
    this.harmonicMix = false,
  });

  static const balanced = DjPolicy();

  double get clampedMinConfidence => minConfidence.clamp(0.20, 0.80);

  /// Floor for profile analysisConfidence before we attempt a musical plan.
  double get analysisFloor => switch (aggressiveness) {
        DjAggressiveness.safe =>
          (clampedMinConfidence < 0.45 ? 0.45 : clampedMinConfidence),
        DjAggressiveness.balanced => clampedMinConfidence,
        DjAggressiveness.musical =>
          (clampedMinConfidence > 0.32 ? 0.32 : clampedMinConfidence),
      };

  /// Multiplier on risk penalties in scoring.
  double get riskPenaltyScale => switch (aggressiveness) {
        DjAggressiveness.safe => 1.40,
        DjAggressiveness.balanced => 1.0,
        DjAggressiveness.musical => 0.70,
      };

  /// Execution planner falls back when risk severity ≥ this.
  double get riskSeverityLimit => switch (aggressiveness) {
        DjAggressiveness.safe => 0.70,
        DjAggressiveness.balanced => 0.90,
        DjAggressiveness.musical => 0.97,
      };

  double kindBias(DjTransitionKind kind) {
    final safeBonus = switch (aggressiveness) {
      DjAggressiveness.safe => 0.14,
      DjAggressiveness.balanced => 0.03,
      DjAggressiveness.musical => -0.03,
    };
    final musicalBonus = switch (aggressiveness) {
      DjAggressiveness.safe => -0.08,
      DjAggressiveness.balanced => 0.0,
      DjAggressiveness.musical => 0.10,
    };
    return switch (kind) {
      DjTransitionKind.safeCrossfade => safeBonus,
      DjTransitionKind.phraseBlend ||
      DjTransitionKind.energyBridge ||
      DjTransitionKind.breakdownDrop =>
        musicalBonus,
      DjTransitionKind.beatBlend || DjTransitionKind.outroIntro =>
        musicalBonus * 0.5,
    };
  }

  /// Learning adjustment clamp for autopilot memory.
  double get learningClamp => switch (aggressiveness) {
        DjAggressiveness.safe => 0.10,
        DjAggressiveness.balanced => 0.22,
        DjAggressiveness.musical => 0.30,
      };

  /// Soft extra weight on phrase continuity when scoring.
  double get phraseWeightBoost => switch (aggressiveness) {
        DjAggressiveness.safe => 0.0,
        DjAggressiveness.balanced => 0.04,
        DjAggressiveness.musical => 0.10,
      };

  bool acceptsCandidate(DjTransitionCandidate c) {
    if (c.kind == DjTransitionKind.safeCrossfade) return true;
    return c.confidence >= clampedMinConfidence && c.score >= 0.32;
  }
}
