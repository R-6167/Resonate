#!/usr/bin/env python3
from pathlib import Path

EST = Path("lib/services/dj_bpm_estimator.dart")
t = EST.read_text()
if "computePhraseAlignedSeekMs" in t:
    print("phrase helper already present")
else:
    helper = '''
/// Align incoming start so the next *phrase* boundary on the outgoing track
/// lands on a phrase boundary of the incoming track (soft; may no-op).
Duration? computePhraseAlignedSeekMs({
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
}

'''
    needle = "return Duration(milliseconds: seek.round());\n}\n\ndouble _mod"
    if needle not in t:
        raise SystemExit("needle miss for phrase helper")
    t = t.replace(needle, "return Duration(milliseconds: seek.round());\n}\n" + helper + "double _mod", 1)
    EST.write_text(t)
    print("phrase helper added")

MP = Path("lib/providers/music_provider.dart")
m = MP.read_text()
changed = False

old_plan = """      final plan = await planDjTransitionLearned(
        analysisA: analysisA,
        analysisB: analysisB,
        tempoMatchActive: _djTempoMatchActive,
        beatAlignActive: _djBeatAlignActive,
        maxStretchPercent: _djMaxStretchPercent,
        fromSongId: outgoingSong.id,
        toSongId: incomingSong.id,
      );
"""
new_plan = """      final outPos = outgoing.position.inMilliseconds;
      final outDur = outgoingSong.duration.inMilliseconds > 0
          ? outgoingSong.duration.inMilliseconds
          : analysisA.durationMs;
      final plan = await planDjTransitionLearned(
        analysisA: analysisA,
        analysisB: analysisB,
        tempoMatchActive: _djTempoMatchActive,
        beatAlignActive: _djBeatAlignActive,
        maxStretchPercent: _djMaxStretchPercent,
        fromSongId: outgoingSong.id,
        toSongId: incomingSong.id,
        outgoingPositionMs: outPos,
        outgoingDurationMs: outDur,
      );
"""
if "outgoingPositionMs:" not in m:
    if old_plan in m:
        m = m.replace(old_plan, new_plan, 1)
        changed = True
        print("wired position into planner")
    else:
        print("WARN: plan call miss")
else:
    print("position already wired")

old_block_start = """      if (plan.attemptBeatAlign) {
        final posMs = outgoing.position.inMilliseconds;
        final seek = computeBeatAlignedSeekMs(
          bpmA: stretch != null ? stretch.effectiveBpm : bpmA,
          beatOffsetMsA: beatOffsetA,
          bpmB: effectiveBpmB,
          beatOffsetMsB: beatOffsetB,
          outgoingPositionMs: posMs,
          maxRelativeDelta: stretch != null ? 0.25 : 0.08,
        );"""
new_block_start = """      if (plan.attemptBeatAlign) {
        final posMs = outgoing.position.inMilliseconds;
        final seek = plan.usePhraseGrid
            ? computePhraseAlignedSeekMs(
                bpmA: stretch != null ? stretch.effectiveBpm : bpmA,
                beatOffsetMsA: beatOffsetA,
                bpmB: effectiveBpmB,
                beatOffsetMsB: beatOffsetB,
                outgoingPositionMs: posMs,
                beatsPerPhrase: plan.phraseBeats,
                maxRelativeDelta: stretch != null ? 0.25 : 0.08,
              )
            : computeBeatAlignedSeekMs(
                bpmA: stretch != null ? stretch.effectiveBpm : bpmA,
                beatOffsetMsA: beatOffsetA,
                bpmB: effectiveBpmB,
                beatOffsetMsB: beatOffsetB,
                outgoingPositionMs: posMs,
                maxRelativeDelta: stretch != null ? 0.25 : 0.08,
              );"""
if "computePhraseAlignedSeekMs" not in m:
    if old_block_start in m:
        m = m.replace(old_block_start, new_block_start, 1)
        changed = True
        print("phrase seek wired")
    else:
        print("WARN: seek block miss")
        # dump nearby for debug
        idx = m.find("plan.attemptBeatAlign")
        if idx >= 0:
            print(repr(m[idx:idx+400]))
else:
    print("phrase seek already")

if changed:
    MP.write_text(m)
    print("music_provider updated")
else:
    print("music_provider unchanged")
print("done")
