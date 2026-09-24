#!/usr/bin/env python3
"""Fine-tune beat matching: half/double BPM, tighter seeks, smarter phrase use."""
from pathlib import Path

EST = Path("lib/services/dj_bpm_estimator.dart")
est = EST.read_text()

# Replace beat + phrase + tempo stretch functions
old_beat = '''Duration? computeBeatAlignedSeekMs({
  required double bpmA,
  required int beatOffsetMsA,
  required double bpmB,
  required int beatOffsetMsB,
  required int outgoingPositionMs,
  double maxRelativeDelta = 0.08,
}) {
  if (bpmA < 40 || bpmB < 40 || bpmA > 240 || bpmB > 240) return null;
  final rel = (bpmA - bpmB).abs() / bpmA;
  if (rel > maxRelativeDelta) return null;

  final periodA = 60000.0 / bpmA;
  final periodB = 60000.0 / bpmB;

  final phaseA = _mod(outgoingPositionMs - beatOffsetMsA, periodA);
  final msToNextBeatA = phaseA < 1e-6 ? 0.0 : (periodA - phaseA);

  var seek = beatOffsetMsB - msToNextBeatA;
  seek = _mod(seek, periodB);

  while (seek > periodB * 8) {
    seek -= periodB;
  }
  if (seek < 0) seek = 0;
  return Duration(milliseconds: seek.round());
}'''

new_beat = '''Duration? computeBeatAlignedSeekMs({
  required double bpmA,
  required int beatOffsetMsA,
  required double bpmB,
  required int beatOffsetMsB,
  required int outgoingPositionMs,
  double maxRelativeDelta = 0.08,
}) {
  if (bpmA < 40 || bpmB < 40 || bpmA > 240 || bpmB > 240) return null;
  final rel = (bpmA - bpmB).abs() / bpmA;
  if (rel > maxRelativeDelta) return null;

  final periodA = 60000.0 / bpmA;
  final periodB = 60000.0 / bpmB;
  // Clamp noisy offsets into one period (PCM peak can be off).
  final offA = _mod(beatOffsetMsA.toDouble(), periodA);
  final offB = _mod(beatOffsetMsB.toDouble(), periodB);

  final phaseA = _mod(outgoingPositionMs - offA, periodA);
  final msToNextBeatA = phaseA < 1.0 ? 0.0 : (periodA - phaseA);

  // Land incoming on a beat when outgoing hits its next beat.
  var seek = offB - msToNextBeatA;
  seek = _mod(seek, periodB);
  // Prefer the nearer phase (don't start almost a full bar in).
  if (seek > periodB * 0.5) {
    seek -= periodB;
  }
  if (seek < 0) seek = 0;
  return Duration(milliseconds: seek.round());
}'''

if old_beat in est:
    est = est.replace(old_beat, new_beat, 1)
    print("beat seek tighter")
else:
    print("WARN beat block miss")

old_phrase = '''Duration? computePhraseAlignedSeekMs({
  required double bpmA,
  required int beatOffsetMsA,
  required double bpmB,
  required int beatOffsetMsB,
  required int outgoingPositionMs,
  int beatsPerPhrase = 4,
  double maxRelativeDelta = 0.08,
}) {
  if (beatsPerPhrase < 2) beatsPerPhrase = 4;
  if (bpmA < 40 || bpmB < 40 || bpmA > 240 || bpmB > 240) return null;
  final rel = (bpmA - bpmB).abs() / bpmA;
  if (rel > maxRelativeDelta) return null;

  final periodA = 60000.0 / bpmA;
  final periodB = 60000.0 / bpmB;
  final phraseA = periodA * beatsPerPhrase;
  final phraseB = periodB * beatsPerPhrase;

  final phaseA = _mod(outgoingPositionMs - beatOffsetMsA, phraseA);
  final msToNextPhraseA = phaseA < 1e-6 ? 0.0 : (phraseA - phaseA);

  var seek = beatOffsetMsB - msToNextPhraseA;
  seek = _mod(seek, phraseB);

  // Keep seek near the top of the incoming track (first few phrases).
  while (seek > phraseB * 2) {
    seek -= phraseB;
  }
  if (seek < 0) seek = 0;
  return Duration(milliseconds: seek.round());
}'''

new_phrase = '''Duration? computePhraseAlignedSeekMs({
  required double bpmA,
  required int beatOffsetMsA,
  required double bpmB,
  required int beatOffsetMsB,
  required int outgoingPositionMs,
  int beatsPerPhrase = 4,
  double maxRelativeDelta = 0.08,
}) {
  if (beatsPerPhrase < 2) beatsPerPhrase = 4;
  if (bpmA < 40 || bpmB < 40 || bpmA > 240 || bpmB > 240) return null;
  final rel = (bpmA - bpmB).abs() / bpmA;
  if (rel > maxRelativeDelta) return null;

  final periodA = 60000.0 / bpmA;
  final periodB = 60000.0 / bpmB;
  final phraseA = periodA * beatsPerPhrase;
  final phraseB = periodB * beatsPerPhrase;
  final offA = _mod(beatOffsetMsA.toDouble(), periodA);
  final offB = _mod(beatOffsetMsB.toDouble(), periodB);

  final phaseA = _mod(outgoingPositionMs - offA, phraseA);
  final msToNextPhraseA = phaseA < 1.0 ? 0.0 : (phraseA - phaseA);

  var seek = offB - msToNextPhraseA;
  seek = _mod(seek, phraseB);
  // At most one phrase into the incoming track (was 2 — felt late on cross-genre).
  if (seek > phraseB) {
    seek -= phraseB;
  }
  // Snap to nearest beat inside the phrase for tighter grids.
  final beatSnap = (seek / periodB).round() * periodB;
  if ((beatSnap - seek).abs() < periodB * 0.35) {
    seek = beatSnap;
  }
  if (seek < 0) seek = 0;
  if (seek >= phraseB) seek = 0;
  return Duration(milliseconds: seek.round());
}'''

if old_phrase in est:
    est = est.replace(old_phrase, new_phrase, 1)
    print("phrase seek tighter")
else:
    print("WARN phrase miss")

old_stretch = '''DjTempoStretchPlan? computeTempoStretch({
  required double bpmA,
  required double bpmB,
  required int maxStretchPercent,
}) {
  if (bpmA < 40 || bpmB < 40 || bpmA > 240 || bpmB > 240) return null;
  final maxDelta = (maxStretchPercent.clamp(3, 20)) / 100.0;
  bool within(double speed) => (speed - 1.0).abs() <= maxDelta + 1e-9;

  final matchIn = bpmA / bpmB;
  if (within(matchIn)) {
    return DjTempoStretchPlan(
      speedOutgoing: 1.0,
      speedIncoming: matchIn,
      effectiveBpm: bpmA,
      mode: 'match_incoming',
    );
  }

  // meet_middle stretches the audible outgoing deck — skip for stability.
  return null;
}'''

new_stretch = '''DjTempoStretchPlan? computeTempoStretch({
  required double bpmA,
  required double bpmB,
  required int maxStretchPercent,
}) {
  if (bpmA < 40 || bpmB < 40 || bpmA > 240 || bpmB > 240) return null;
  final maxDelta = (maxStretchPercent.clamp(3, 20)) / 100.0;
  bool within(double speed) => (speed - 1.0).abs() <= maxDelta + 1e-9;

  // Prefer direct match, then half/double (common cross-genre / wrong-octave BPM).
  DjTempoStretchPlan? best;
  void consider(double candidateBpmB, String mode) {
    if (candidateBpmB < 40 || candidateBpmB > 240) return;
    final matchIn = bpmA / candidateBpmB;
    if (!within(matchIn)) return;
    final plan = DjTempoStretchPlan(
      speedOutgoing: 1.0,
      speedIncoming: matchIn,
      effectiveBpm: bpmA,
      mode: mode,
    );
    if (best == null ||
        (matchIn - 1.0).abs() < (best!.speedIncoming - 1.0).abs()) {
      best = plan;
    }
  }

  consider(bpmB, 'match_incoming');
  consider(bpmB / 2.0, 'match_incoming_half');
  consider(bpmB * 2.0, 'match_incoming_double');
  return best;
}'''

if old_stretch in est:
    est = est.replace(old_stretch, new_stretch, 1)
    print("stretch half/double")
else:
    print("WARN stretch miss")

EST.write_text(est)

# ---------- Planner: tighter phrase gating ----------
PL = Path("lib/services/dj_transition_planner.dart")
pl = PL.read_text()

old_gate = '''  // Soft phrase grid when beat align is on and BPMs are close enough for a
  // 4-beat phrase (relative delta under ~8% without stretch, or stretch present).
  final rel = (bpmA - bpmB).abs() / bpmA;
  final phraseOk = tryBeat && (stretch != null || rel <= 0.08);'''

new_gate = '''  // Phrase grid only when tempos are already close *or* locked by stretch.
  // Cross-genre pairs with only stretch → single-beat align (tighter than a bar).
  final rel = (bpmA - bpmB).abs() / math.max(bpmA, 1.0);
  final confOk =
      analysisA.bpmConfidence >= 0.45 && analysisB.bpmConfidence >= 0.45;
  final phraseOk = tryBeat &&
      confOk &&
      (rel <= 0.04 || (stretch != null && rel <= 0.12));'''

if "confOk" not in pl:
    if old_gate not in pl:
        print("WARN gate miss")
    else:
        pl = pl.replace(old_gate, new_gate, 1)
        print("phrase gate")
    if "import 'dart:math' as math;" not in pl:
        pl = "import 'dart:math' as math;\n" + pl

# Prefer 8-beat phrases on outro when both confident
old_outro = '''  if (outro && (stretch != null || tryBeat)) {
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
      crossfadeBiasMs: biasFor('outro_intro'),
      usePhraseGrid: phraseOk,
      phraseBeats: 4,
    );
  }'''

new_outro = '''  if (outro && (stretch != null || tryBeat)) {
    final phraseBeats = (phraseOk && confOk) ? 8 : 4;
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
      crossfadeBiasMs: biasFor('outro_intro'),
      usePhraseGrid: phraseOk,
      phraseBeats: phraseBeats,
    );
  }'''

if "phraseBeats = (phraseOk && confOk)" not in pl:
    if old_outro in pl:
        pl = pl.replace(old_outro, new_outro, 1)
        print("outro 8-beat")
    else:
        print("WARN outro miss")

# Soft: when energy very different, prefer tempo-only over beat seek
old_energy = '''  // Soft: extreme energy jump + aggressive mix → prefer tempo-only + longer bridge.
  if ((plan.strategy == 'beat_tempo' ||
          plan.strategy == 'phrase_align' ||
          plan.strategy == 'outro_intro') &&
      plan.energyScore < 0.35) {
    plan = plan.copyWith(
      strategy: 'tempo_match',
      attemptBeatAlign: false,
      reason: 'energy_mismatch_soft',
      usePhraseGrid: false,
      crossfadeBiasMs: (plan.crossfadeBiasMs + 800).clamp(-1500, 2500).toInt(),
    );
  }'''

new_energy = '''  // Soft: energy jump → drop beat seek (tempo lock only) + slightly longer bridge.
  if ((plan.strategy == 'beat_tempo' ||
          plan.strategy == 'phrase_align' ||
          plan.strategy == 'outro_intro') &&
      plan.energyScore < 0.45) {
    plan = plan.copyWith(
      strategy: 'tempo_match',
      attemptBeatAlign: false,
      reason: 'energy_mismatch_soft',
      usePhraseGrid: false,
      crossfadeBiasMs: (plan.crossfadeBiasMs + 600).clamp(-1500, 2500).toInt(),
    );
  }'''

if "energyScore < 0.45" not in pl:
    if old_energy in pl:
        pl = pl.replace(old_energy, new_energy, 1)
        print("energy demote 0.45")

PL.write_text(pl)

# ---------- music_provider: slightly tighter maxRelative when no stretch ----------
MP = Path("lib/providers/music_provider.dart")
mp = MP.read_text()
mp2 = mp.replace(
    "maxRelativeDelta: stretch != null ? 0.25 : 0.08,",
    "maxRelativeDelta: stretch != null ? 0.18 : 0.055,",
)
if mp2 != mp:
    mp = mp2
    print("relative delta tighter")
    MP.write_text(mp)
else:
    print("delta already or miss")

print("ALL FINE-TUNE DONE")
