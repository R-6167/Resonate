#!/usr/bin/env python3
"""Fine-tune beat matching: half/double BPM, tighter seeks, smarter phrase use."""
from pathlib import Path

EST = Path("lib/services/dj_bpm_estimator.dart")
est = EST.read_text()

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
  final offA = _mod(beatOffsetMsA.toDouble(), periodA);
  final offB = _mod(beatOffsetMsB.toDouble(), periodB);

  final phaseA = _mod(outgoingPositionMs - offA, periodA);
  final msToNextBeatA = phaseA < 1.0 ? 0.0 : (periodA - phaseA);

  var seek = offB - msToNextBeatA;
  seek = _mod(seek, periodB);
  if (seek > periodB * 0.5) {
    seek -= periodB;
  }
  if (seek < 0) seek = 0;
  return Duration(milliseconds: seek.round());
}'''

if 'nearer phase' in est or 'periodB * 0.5' in est:
    print('beat already')
elif old_beat in est:
    est = est.replace(old_beat, new_beat, 1)
    print('beat seek tighter')
else:
    raise SystemExit('beat block miss')

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
  if (seek > phraseB) {
    seek -= phraseB;
  }
  final beatSnap = (seek / periodB).round() * periodB;
  if ((beatSnap - seek).abs() < periodB * 0.35) {
    seek = beatSnap;
  }
  if (seek < 0) seek = 0;
  if (seek >= phraseB) seek = 0;
  return Duration(milliseconds: seek.round());
}'''

if 'beatSnap' in est:
    print('phrase already')
elif old_phrase in est:
    est = est.replace(old_phrase, new_phrase, 1)
    print('phrase seek tighter')
else:
    raise SystemExit('phrase miss')

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

if 'match_incoming_half' in est:
    print('stretch already')
elif old_stretch in est:
    est = est.replace(old_stretch, new_stretch, 1)
    print('stretch half/double')
else:
    raise SystemExit('stretch miss')

EST.write_text(est)
print('estimator ok')

PL = Path('lib/services/dj_transition_planner.dart')
pl = PL.read_text()
if "import 'dart:math' as math;" not in pl:
    pl = "import 'dart:math' as math;\n" + pl

if 'confOk' not in pl:
    old_gate = '''  // Soft phrase grid when beat align is on and BPMs are close enough for a
  // 4-beat phrase (relative delta under ~8% without stretch, or stretch present).
  final rel = (bpmA - bpmB).abs() / bpmA;
  final phraseOk = tryBeat && (stretch != null || rel <= 0.08);'''
    new_gate = '''  final rel = (bpmA - bpmB).abs() / math.max(bpmA, 1.0);
  final confOk =
      analysisA.bpmConfidence >= 0.45 && analysisB.bpmConfidence >= 0.45;
  final phraseOk = tryBeat &&
      confOk &&
      (rel <= 0.04 || (stretch != null && rel <= 0.12));'''
    if old_gate not in pl:
        raise SystemExit('gate miss')
    pl = pl.replace(old_gate, new_gate, 1)
    print('phrase gate')

if 'phraseBeats = (phraseOk && confOk)' not in pl:
    pl = pl.replace(
        'usePhraseGrid: phraseOk,\n      phraseBeats: 4,\n    );\n  }\n\n  if (phraseOk && stretch != null)',
        'usePhraseGrid: phraseOk,\n      phraseBeats: (phraseOk && confOk) ? 8 : 4,\n    );\n  }\n\n  if (phraseOk && stretch != null)',
        1,
    )
    print('outro phrase beats')

if 'energyScore < 0.45' not in pl:
    pl = pl.replace('plan.energyScore < 0.35)', 'plan.energyScore < 0.45)', 1)
    pl = pl.replace(
        'crossfadeBiasMs: (plan.crossfadeBiasMs + 800).clamp(-1500, 2500).toInt()',
        'crossfadeBiasMs: (plan.crossfadeBiasMs + 600).clamp(-1500, 2500).toInt()',
        1,
    )
    print('energy demote')

PL.write_text(pl)

MP = Path('lib/providers/music_provider.dart')
mp = MP.read_text()
n = mp.replace(
    'maxRelativeDelta: stretch != null ? 0.25 : 0.08,',
    'maxRelativeDelta: stretch != null ? 0.18 : 0.055,',
)
if n != mp:
    MP.write_text(n)
    print('delta tighter')
else:
    print('delta already')

print('ALL DONE')
