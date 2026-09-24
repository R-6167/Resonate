import '../models/dj_analysis.dart';
import 'dj_bpm_estimator.dart';
import 'dj_harmonic.dart';

/// Autonomous transition choice for DJ Mode.
///
/// Strategies are soft: the dual-engine crossfade always runs. This only decides
/// optional beat seek / tempo stretch. Missing analysis → safe_fallback.
class DjTransitionPlan {
  /// safe_fallback | tempo_match | beat_align | beat_tempo
  final String strategy;
  final double harmonicScore;
  final DjTempoStretchPlan? stretch;
  final bool attemptBeatAlign;
  final String reason;
  final double? bpmA;
  final double? bpmB;
  final double confidenceA;
  final double confidenceB;

  const DjTransitionPlan({
    required this.strategy,
    required this.harmonicScore,
    required this.stretch,
    required this.attemptBeatAlign,
    required this.reason,
    this.bpmA,
    this.bpmB,
    this.confidenceA = 0,
    this.confidenceB = 0,
  });

  Map<String, dynamic> toDiagExtra() => {
        'strategy': strategy,
        'reason': reason,
        'harmonicScore': harmonicScore,
        'bpmA': bpmA,
        'bpmB': bpmB,
        'confidenceA': confidenceA,
        'confidenceB': confidenceB,
        'hasStretch': stretch != null,
        'attemptBeatAlign': attemptBeatAlign,
        if (stretch != null) 'stretchMode': stretch!.mode,
        if (stretch != null) 'speedIn': stretch!.speedIncoming,
      };
}

/// Plan the best *optional* DJ assist for this handoff. Never rejects playback.
DjTransitionPlan planDjTransition({
  required DjAnalysis analysisA,
  required DjAnalysis analysisB,
  required bool tempoMatchActive,
  required bool beatAlignActive,
  required int maxStretchPercent,
}) {
  final harmonic = harmonicCompatibility(
    rootA: analysisA.keyRoot,
    modeA: analysisA.keyMode,
    rootB: analysisB.keyRoot,
    modeB: analysisB.keyMode,
  );

  final hasA = analysisA.hasUsableBpm;
  final hasB = analysisB.hasUsableBpm;

  if (!hasA || !hasB) {
    return DjTransitionPlan(
      strategy: 'safe_fallback',
      harmonicScore: harmonic,
      stretch: null,
      attemptBeatAlign: false,
      reason: !hasA && !hasB
          ? 'missing_bpm_both'
          : (!hasA ? 'missing_bpm_outgoing' : 'missing_bpm_incoming'),
      bpmA: analysisA.bpm,
      bpmB: analysisB.bpm,
      confidenceA: analysisA.bpmConfidence,
      confidenceB: analysisB.bpmConfidence,
    );
  }

  final bpmA = analysisA.bpm!;
  final bpmB = analysisB.bpm!;

  DjTempoStretchPlan? stretch;
  if (tempoMatchActive) {
    stretch = computeTempoStretch(
      bpmA: bpmA,
      bpmB: bpmB,
      maxStretchPercent: maxStretchPercent,
    );
  }

  final tryBeat = beatAlignActive;
  if (stretch != null && tryBeat) {
    return DjTransitionPlan(
      strategy: 'beat_tempo',
      harmonicScore: harmonic,
      stretch: stretch,
      attemptBeatAlign: true,
      reason: 'bpm_compatible',
      bpmA: bpmA,
      bpmB: bpmB,
      confidenceA: analysisA.bpmConfidence,
      confidenceB: analysisB.bpmConfidence,
    );
  }
  if (stretch != null) {
    return DjTransitionPlan(
      strategy: 'tempo_match',
      harmonicScore: harmonic,
      stretch: stretch,
      attemptBeatAlign: false,
      reason: 'tempo_only',
      bpmA: bpmA,
      bpmB: bpmB,
      confidenceA: analysisA.bpmConfidence,
      confidenceB: analysisB.bpmConfidence,
    );
  }
  if (tryBeat) {
    // Beat align may still no-op if relative delta is large (handled at seek time).
    return DjTransitionPlan(
      strategy: 'beat_align',
      harmonicScore: harmonic,
      stretch: null,
      attemptBeatAlign: true,
      reason: tempoMatchActive ? 'stretch_budget' : 'beat_only',
      bpmA: bpmA,
      bpmB: bpmB,
      confidenceA: analysisA.bpmConfidence,
      confidenceB: analysisB.bpmConfidence,
    );
  }

  return DjTransitionPlan(
    strategy: 'safe_fallback',
    harmonicScore: harmonic,
    stretch: null,
    attemptBeatAlign: false,
    reason: 'features_off',
    bpmA: bpmA,
    bpmB: bpmB,
    confidenceA: analysisA.bpmConfidence,
    confidenceB: analysisB.bpmConfidence,
  );
}
