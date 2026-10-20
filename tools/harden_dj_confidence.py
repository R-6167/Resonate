#!/usr/bin/env python3
"""Make DJ Mode more confident: fewer beat skips, better half/double, softer demote."""
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
MUSIC = ROOT / 'lib/providers/music_provider.dart'
BPM = ROOT / 'lib/services/dj_bpm_estimator.dart'
PLAN = ROOT / 'lib/services/dj_transition_planner.dart'
HARM = ROOT / 'lib/services/dj_harmonic.dart'


def try_replace(path: Path, old: str, new: str, label: str) -> bool:
    t = path.read_text()
    if old not in t:
        print('skip', label)
        return False
    path.write_text(t.replace(old, new, 1))
    print('ok', label)
    return True


def main() -> None:
    # --- Wider beat-align tolerance at handoff ---
    try_replace(
        MUSIC,
        'maxRelativeDelta: stretch != null ? 0.18 : 0.055,',
        'maxRelativeDelta: stretch != null ? 0.22 : 0.09,',
        'music_max_rel_phrase',
    )
    # second occurrence for beat-only path
    t = MUSIC.read_text()
    if 'maxRelativeDelta: stretch != null ? 0.18 : 0.055,' in t:
        MUSIC.write_text(
            t.replace(
                'maxRelativeDelta: stretch != null ? 0.18 : 0.055,',
                'maxRelativeDelta: stretch != null ? 0.22 : 0.09,',
                1,
            )
        )
        print('ok music_max_rel_beat')
    elif t.count('maxRelativeDelta: stretch != null ? 0.22 : 0.09,') >= 1:
        # replace remaining 0.055 if any
        if '0.055' in t and 'maxRelativeDelta' in t:
            MUSIC.write_text(
                t.replace(
                    'maxRelativeDelta: stretch != null ? 0.18 : 0.055,',
                    'maxRelativeDelta: stretch != null ? 0.22 : 0.09,',
                )
            )
        print('ok music_max_rel already partially')

    # Default stretch budget 12 → 14 (still not cocky)
    try_replace(
        MUSIC,
        'int _djMaxStretchPercent = 12;',
        'int _djMaxStretchPercent = 14;',
        'stretch_default_14',
    )

    # Slightly longer dual repeat fade (user liked A→B but said short)
    try_replace(
        MUSIC,
        'final loopMs = _crossfadeDurationMs.clamp(1200, 4000);',
        'final loopMs = _crossfadeDurationMs.clamp(1600, 5500);',
        'repeat_dual_longer',
    )

    # --- BPM estimator: smarter relative check with half/double ---
    try_replace(
        BPM,
        '''Duration? computeBeatAlignedSeekMs({
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
  final periodB = 60000.0 / bpmB;''',
        '''/// Prefer the BPM octave (1× / ½ / 2×) closest to [bpmA] for phase math.
double _effectiveBpmForAlign(double bpmA, double bpmB) {
  var best = bpmB;
  var bestRel = (bpmA - bpmB).abs() / math.max(bpmA, 1.0);
  for (final cand in [bpmB * 0.5, bpmB * 2.0]) {
    if (cand < 40 || cand > 240) continue;
    final r = (bpmA - cand).abs() / math.max(bpmA, 1.0);
    if (r < bestRel) {
      bestRel = r;
      best = cand;
    }
  }
  return best;
}

Duration? computeBeatAlignedSeekMs({
  required double bpmA,
  required int beatOffsetMsA,
  required double bpmB,
  required int beatOffsetMsB,
  required int outgoingPositionMs,
  double maxRelativeDelta = 0.09,
}) {
  if (bpmA < 40 || bpmB < 40 || bpmA > 240 || bpmB > 240) return null;
  // Half/double often looks like a huge delta but is the same pulse grid.
  final bpmBEff = _effectiveBpmForAlign(bpmA, bpmB);
  final rel = (bpmA - bpmBEff).abs() / math.max(bpmA, 1.0);
  if (rel > maxRelativeDelta) return null;

  final periodA = 60000.0 / bpmA;
  final periodB = 60000.0 / bpmBEff;''',
        'beat_align_half_double',
    )

    try_replace(
        BPM,
        '''Duration? computePhraseAlignedSeekMs({
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
  final periodB = 60000.0 / bpmB;''',
        '''Duration? computePhraseAlignedSeekMs({
  required double bpmA,
  required int beatOffsetMsA,
  required double bpmB,
  required int beatOffsetMsB,
  required int outgoingPositionMs,
  int beatsPerPhrase = 4,
  double maxRelativeDelta = 0.09,
}) {
  if (beatsPerPhrase < 2) beatsPerPhrase = 4;
  if (bpmA < 40 || bpmB < 40 || bpmA > 240 || bpmB > 240) return null;
  final bpmBEff = _effectiveBpmForAlign(bpmA, bpmB);
  final rel = (bpmA - bpmBEff).abs() / math.max(bpmA, 1.0);
  if (rel > maxRelativeDelta) return null;

  final periodA = 60000.0 / bpmA;
  final periodB = 60000.0 / bpmBEff;''',
        'phrase_align_half_double',
    )

    try_replace(
        BPM,
        'final maxDelta = (maxStretchPercent.clamp(3, 20)) / 100.0;',
        'final maxDelta = (maxStretchPercent.clamp(3, 22)) / 100.0;',
        'stretch_clamp_22',
    )

    # --- Planner: slightly easier phrase/outro confidence ---
    try_replace(
        PLAN,
        '''  final confOk =
      analysisA.bpmConfidence >= 0.45 && analysisB.bpmConfidence >= 0.45;
  final phraseOk = tryBeat &&
      confOk &&
      (rel <= 0.04 || (stretch != null && rel <= 0.12));''',
        '''  final confOk =
      analysisA.bpmConfidence >= 0.40 && analysisB.bpmConfidence >= 0.40;
  // Confident but not cocky: allow a bit more relative delta before phrase grid.
  final phraseOk = tryBeat &&
      confOk &&
      (rel <= 0.06 || (stretch != null && rel <= 0.16));''',
        'planner_conf_phrase',
    )

    try_replace(
        PLAN,
        '''  final hostilePair = pair < -0.35;
  final hostileStrat = stratBias < -0.45;''',
        '''  // Need clearer negative history before demoting (fewer "skips" from learning).
  final hostilePair = pair < -0.50;
  final hostileStrat = stratBias < -0.55;''',
        'learn_demote_softer',
    )

    # Soft energy demote threshold slightly lower (only very big jumps)
    try_replace(
        PLAN,
        '      plan.energyScore < 0.45) {',
        '      plan.energyScore < 0.32) {',
        'energy_demote_softer',
    )

    # --- Harmonic: mild score for distant keys (not hard zero) ---
    try_replace(
        HARM,
        '''  if (dist == 1 && a.letter == b.letter) return 0.72;
  if (dist == 1) return 0.45;
  if (dist == 2 && a.letter == b.letter) return 0.35;
  return 0.0;''',
        '''  if (dist == 1 && a.letter == b.letter) return 0.72;
  if (dist == 1) return 0.48;
  if (dist == 2 && a.letter == b.letter) return 0.38;
  if (dist == 2) return 0.22;
  if (dist == 3 && a.letter == b.letter) return 0.18;
  // Soft floor — never a hard "incompatible" zero for energy-bridge bias.
  return 0.12;''',
        'harmonic_soft_floor',
    )

    print('dj confidence harden done')


if __name__ == '__main__':
    main()
