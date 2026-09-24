import '../models/dj_analysis.dart';
import 'dj_bpm_estimator.dart';
import 'dj_harmonic.dart';
import 'dj_transition_memory.dart';

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
  /// Soft learning scores in [-1, 1] (positive = past completes beat early skips).
  final double pairBias;
  final double strategyBias;

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
    this.pairBias = 0,
    this.strategyBias = 0,
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
        'pairBias': pairBias,
        'strategyBias': strategyBias,
        if (stretch != null) 'stretchMode': stretch!.mode,
        if (stretch != null) 'speedIn': stretch!.speedIncoming,
      };

  DjTransitionPlan copyWith({
    String? strategy,
    DjTempoStretchPlan? stretch,
    bool? attemptBeatAlign,
    String? reason,
    double? pairBias,
    double? strategyBias,
    bool clearStretch = false,
  }) {
    return DjTransitionPlan(
      strategy: strategy ?? this.strategy,
      harmonicScore: harmonicScore,
      stretch: clearStretch ? null : (stretch ?? this.stretch),
      attemptBeatAlign: attemptBeatAlign ?? this.attemptBeatAlign,
      reason: reason ?? this.reason,
      bpmA: bpmA,
      bpmB: bpmB,
      confidenceA: confidenceA,
      confidenceB: confidenceB,
      pairBias: pairBias ?? this.pairBias,
      strategyBias: strategyBias ?? this.strategyBias,
    );
  }
}

/// Sync planner (no learning). Prefer [planDjTransitionLearned] at handoff.
DjTransitionPlan planDjTransition({
  required DjAnalysis analysisA,
  required DjAnalysis analysisB,
  required bool tempoMatchActive,
  required bool beatAlignActive,
  required int maxStretchPercent,
  double pairBias = 0,
  double strategyBias = 0,
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
      pairBias: pairBias,
      strategyBias: strategyBias,
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
      pairBias: pairBias,
      strategyBias: strategyBias,
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
      pairBias: pairBias,
      strategyBias: strategyBias,
    );
  }
  if (tryBeat) {
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
      pairBias: pairBias,
      strategyBias: strategyBias,
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
    pairBias: pairBias,
    strategyBias: strategyBias,
  );
}

/// Async planner that soft-demotes aggressive strategies when learning says they
/// failed often for this pair / strategy. Never blocks; never hard-rejects play.
Future<DjTransitionPlan> planDjTransitionLearned({
  required DjAnalysis analysisA,
  required DjAnalysis analysisB,
  required bool tempoMatchActive,
  required bool beatAlignActive,
  required int maxStretchPercent,
  String? fromSongId,
  String? toSongId,
}) async {
  final pair = (fromSongId != null &&
          toSongId != null &&
          fromSongId.isNotEmpty &&
          toSongId.isNotEmpty)
      ? await DjTransitionMemory.pairBias(fromSongId, toSongId)
      : 0.0;

  var plan = planDjTransition(
    analysisA: analysisA,
    analysisB: analysisB,
    tempoMatchActive: tempoMatchActive,
    beatAlignActive: beatAlignActive,
    maxStretchPercent: maxStretchPercent,
    pairBias: pair,
  );

  final stratBias = await DjTransitionMemory.strategyBias(plan.strategy);
  plan = plan.copyWith(strategyBias: stratBias);

  // Soft demote only when history is clearly negative.
  final hostilePair = pair < -0.35;
  final hostileStrat = stratBias < -0.45;

  if (plan.strategy == 'beat_tempo' && (hostilePair || hostileStrat)) {
    if (plan.stretch != null && !hostilePair) {
      return plan.copyWith(
        strategy: 'tempo_match',
        attemptBeatAlign: false,
        reason: 'learn_demote_beat',
        strategyBias: stratBias,
      );
    }
    return plan.copyWith(
      strategy: 'safe_fallback',
      attemptBeatAlign: false,
      reason: 'learn_demote_aggressive',
      clearStretch: true,
      strategyBias: stratBias,
    );
  }

  if (plan.strategy == 'tempo_match' && hostilePair && hostileStrat) {
    return plan.copyWith(
      strategy: 'safe_fallback',
      attemptBeatAlign: false,
      reason: 'learn_demote_tempo',
      clearStretch: true,
      strategyBias: stratBias,
    );
  }

  if (plan.strategy == 'beat_align' && hostilePair) {
    return plan.copyWith(
      strategy: 'safe_fallback',
      attemptBeatAlign: false,
      reason: 'learn_demote_beat',
      strategyBias: stratBias,
    );
  }

  return plan;
}
