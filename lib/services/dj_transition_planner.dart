import '../models/dj_analysis.dart';
import 'dj_bpm_estimator.dart';
import 'dj_harmonic.dart';
import 'dj_transition_memory.dart';

/// Soft energy compatibility in [0, 1]. Neutral 0.5 when either side unknown.
double energyCompatibility(double? a, double? b) {
  if (a == null || b == null) return 0.5;
  final d = (a - b).abs().clamp(0.0, 1.0);
  return (1.0 - d);
}

/// True when the outgoing track is in a soft "outro" window (near end).
/// Uses duration + position only — no section detector required.
bool inOutroWindow({
  required int? durationMs,
  required int positionMs,
}) {
  if (durationMs == null || durationMs < 45000) return false;
  if (positionMs < 0) return false;
  final remaining = durationMs - positionMs;
  if (remaining < 2800) return false;
  final thresh = durationMs < 120000
      ? 14000
      : (durationMs * 0.14).round().clamp(16000, 28000);
  return remaining <= thresh;
}

/// Autonomous transition choice for DJ Mode.
///
/// Strategies are soft: the dual-engine crossfade always runs. This only decides
/// optional beat seek / tempo stretch / phrase grid. Missing analysis → safe_fallback.
class DjTransitionPlan {
  /// safe_fallback | tempo_match | beat_align | beat_tempo | phrase_align | outro_intro
  final String strategy;
  final double harmonicScore;
  final DjTempoStretchPlan? stretch;
  final bool attemptBeatAlign;
  final String reason;
  final double? bpmA;
  final double? bpmB;
  final double confidenceA;
  final double confidenceB;
  /// Soft energy compatibility 0–1 (1 = similar energy; 0.5 = unknown).
  final double energyScore;
  /// Soft learning scores in [-1, 1] (positive = past completes beat early skips).
  final double pairBias;
  final double strategyBias;
  /// When true, beat seek snaps to a multi-beat phrase grid (usually 4).
  final bool usePhraseGrid;
  final int phraseBeats;

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
    this.energyScore = 0.5,
    this.pairBias = 0,
    this.strategyBias = 0,
    this.usePhraseGrid = false,
    this.phraseBeats = 4,
  });

  Map<String, dynamic> toDiagExtra() => {
        'strategy': strategy,
        'reason': reason,
        'harmonicScore': harmonicScore,
        'bpmA': bpmA,
        'bpmB': bpmB,
        'confidenceA': confidenceA,
        'confidenceB': confidenceB,
        'energyScore': energyScore,
        'hasStretch': stretch != null,
        'attemptBeatAlign': attemptBeatAlign,
        'pairBias': pairBias,
        'strategyBias': strategyBias,
        'usePhraseGrid': usePhraseGrid,
        'phraseBeats': phraseBeats,
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
    bool? usePhraseGrid,
    int? phraseBeats,
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
      energyScore: energyScore,
      pairBias: pairBias ?? this.pairBias,
      strategyBias: strategyBias ?? this.strategyBias,
      usePhraseGrid: usePhraseGrid ?? this.usePhraseGrid,
      phraseBeats: phraseBeats ?? this.phraseBeats,
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
  int? outgoingPositionMs,
  int? outgoingDurationMs,
}) {
  final harmonic = harmonicCompatibility(
    rootA: analysisA.keyRoot,
    modeA: analysisA.keyMode,
    rootB: analysisB.keyRoot,
    modeB: analysisB.keyMode,
  );
  final energyScore = energyCompatibility(analysisA.energy, analysisB.energy);

  final hasA = analysisA.hasUsableBpm;
  final hasB = analysisB.hasUsableBpm;

  if (!hasA || !hasB) {
    return DjTransitionPlan(
      strategy: 'safe_fallback',
      harmonicScore: harmonic,
      energyScore: energyScore,
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
  final outro = outgoingPositionMs != null &&
      inOutroWindow(
        durationMs: outgoingDurationMs ?? analysisA.durationMs,
        positionMs: outgoingPositionMs,
      );

  // Soft phrase grid when beat align is on and BPMs are close enough for a
  // 4-beat phrase (relative delta under ~8% without stretch, or stretch present).
  final rel = (bpmA - bpmB).abs() / bpmA;
  final phraseOk = tryBeat && (stretch != null || rel <= 0.08);

  if (outro && (stretch != null || tryBeat)) {
    return DjTransitionPlan(
      strategy: 'outro_intro',
      harmonicScore: harmonic,
      energyScore: energyScore,
      stretch: stretch,
      attemptBeatAlign: tryBeat,
      reason: 'outro_window',
      bpmA: bpmA,
      bpmB: bpmB,
      confidenceA: analysisA.bpmConfidence,
      confidenceB: analysisB.bpmConfidence,
      pairBias: pairBias,
      strategyBias: strategyBias,
      usePhraseGrid: phraseOk,
      phraseBeats: 4,
    );
  }

  if (phraseOk && stretch != null) {
    return DjTransitionPlan(
      strategy: 'phrase_align',
      harmonicScore: harmonic,
      energyScore: energyScore,
      stretch: stretch,
      attemptBeatAlign: true,
      reason: 'phrase_grid_4',
      bpmA: bpmA,
      bpmB: bpmB,
      confidenceA: analysisA.bpmConfidence,
      confidenceB: analysisB.bpmConfidence,
      pairBias: pairBias,
      strategyBias: strategyBias,
      usePhraseGrid: true,
      phraseBeats: 4,
    );
  }

  if (stretch != null && tryBeat) {
    return DjTransitionPlan(
      strategy: 'beat_tempo',
      harmonicScore: harmonic,
      energyScore: energyScore,
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
      energyScore: energyScore,
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
      strategy: phraseOk ? 'phrase_align' : 'beat_align',
      harmonicScore: harmonic,
      energyScore: energyScore,
      stretch: null,
      attemptBeatAlign: true,
      reason: phraseOk
          ? 'phrase_grid_4'
          : (tempoMatchActive ? 'stretch_budget' : 'beat_only'),
      bpmA: bpmA,
      bpmB: bpmB,
      confidenceA: analysisA.bpmConfidence,
      confidenceB: analysisB.bpmConfidence,
      pairBias: pairBias,
      strategyBias: strategyBias,
      usePhraseGrid: phraseOk,
      phraseBeats: 4,
    );
  }

  return DjTransitionPlan(
    strategy: 'safe_fallback',
    harmonicScore: harmonic,
    energyScore: energyScore,
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
  int? outgoingPositionMs,
  int? outgoingDurationMs,
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
    outgoingPositionMs: outgoingPositionMs,
    outgoingDurationMs: outgoingDurationMs,
  );

  final stratBias = await DjTransitionMemory.strategyBias(plan.strategy);
  plan = plan.copyWith(strategyBias: stratBias);

  // Soft: extreme energy jump + aggressive mix → prefer tempo-only.
  if ((plan.strategy == 'beat_tempo' ||
          plan.strategy == 'phrase_align' ||
          plan.strategy == 'outro_intro') &&
      plan.energyScore < 0.35) {
    plan = plan.copyWith(
      strategy: 'tempo_match',
      attemptBeatAlign: false,
      reason: 'energy_mismatch_soft',
      usePhraseGrid: false,
    );
  }

  // Soft demote only when history is clearly negative.
  final hostilePair = pair < -0.35;
  final hostileStrat = stratBias < -0.45;

  final aggressive = plan.strategy == 'beat_tempo' ||
      plan.strategy == 'phrase_align' ||
      plan.strategy == 'outro_intro';

  if (aggressive && (hostilePair || hostileStrat)) {
    if (plan.stretch != null && !hostilePair) {
      return plan.copyWith(
        strategy: 'tempo_match',
        attemptBeatAlign: false,
        reason: 'learn_demote_beat',
        strategyBias: stratBias,
        usePhraseGrid: false,
      );
    }
    return plan.copyWith(
      strategy: 'safe_fallback',
      attemptBeatAlign: false,
      reason: 'learn_demote_aggressive',
      clearStretch: true,
      strategyBias: stratBias,
      usePhraseGrid: false,
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
      usePhraseGrid: false,
    );
  }

  return plan;
}
