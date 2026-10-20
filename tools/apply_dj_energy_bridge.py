#!/usr/bin/env python3
from pathlib import Path

MP = Path("lib/providers/music_provider.dart")
m = MP.read_text()

if "_lastDjCrossfadeBiasMs" not in m:
    old = "  String? _lastDjStrategy;\n"
    new = "  String? _lastDjStrategy;\n  /// Soft energy-bridge bias applied to the next crossfade length (ms).\n  int _lastDjCrossfadeBiasMs = 0;\n"
    if old not in m:
        raise SystemExit("field anchor miss")
    m = m.replace(old, new, 1)
    print("field added")
else:
    print("field already")

# Reset at start of prepare
if "_lastDjCrossfadeBiasMs = 0;" not in m.split("_prepareDjHandoff")[1][:400]:
    old = """  Future<void> _prepareDjHandoff({
    required AudioPlayer outgoing,
    required AudioPlayer incoming,
    required Song? outgoingSong,
    required Song incomingSong,
  }) async {
    if ((!_djBeatAlignActive && !_djTempoMatchActive) || _djAnalysis == null) {
      return;
    }
"""
    new = """  Future<void> _prepareDjHandoff({
    required AudioPlayer outgoing,
    required AudioPlayer incoming,
    required Song? outgoingSong,
    required Song incomingSong,
  }) async {
    _lastDjCrossfadeBiasMs = 0;
    if ((!_djBeatAlignActive && !_djTempoMatchActive) || _djAnalysis == null) {
      return;
    }
"""
    if old not in m:
        raise SystemExit("prepare head miss")
    m = m.replace(old, new, 1)
    print("prepare reset")
else:
    print("prepare reset already")

# After plan is obtained, store bias (even on safe_fallback)
if "_lastDjCrossfadeBiasMs = plan.crossfadeBiasMs" not in m:
    old = """      final plan = await planDjTransitionLearned(
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

      if (plan.strategy == 'safe_fallback') {
"""
    new = """      final plan = await planDjTransitionLearned(
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
      _lastDjCrossfadeBiasMs = plan.crossfadeBiasMs;

      if (plan.strategy == 'safe_fallback') {
"""
    if old not in m:
        raise SystemExit("plan store miss")
    m = m.replace(old, new, 1)
    print("bias stored")
else:
    print("bias store already")

# Apply bias to plannedMs
old_planned = "final plannedMs = milliseconds.clamp(500, 12000).toInt();"
new_planned = "final plannedMs = (milliseconds + _lastDjCrossfadeBiasMs).clamp(500, 12000).toInt();"
if new_planned in m:
    print("plannedMs already biased")
elif old_planned in m:
    m = m.replace(old_planned, new_planned, 1)
    print("plannedMs biased")
else:
    raise SystemExit("plannedMs miss")

# Diagnostics on bias when non-zero — optional near plannedMs
if "crossfade_energy_bridge" not in m:
    old = "final plannedMs = (milliseconds + _lastDjCrossfadeBiasMs).clamp(500, 12000).toInt();\n      int remainingMs = plannedMs;"
    new = "final plannedMs = (milliseconds + _lastDjCrossfadeBiasMs).clamp(500, 12000).toInt();\n      if (_lastDjCrossfadeBiasMs != 0) {\n        unawaited(ResonateDiagnostics.record('crossfade_energy_bridge', {\n          'biasMs': _lastDjCrossfadeBiasMs,\n          'baseMs': milliseconds,\n          'plannedMs': plannedMs,\n          'outgoingSongId': outgoingSong?.id,\n          'incomingSongId': nextSong.id,\n        }));\n      }\n      int remainingMs = plannedMs;"
    if old in m:
        m = m.replace(old, new, 1)
        print("diag added")
    else:
        print("WARN diag skip")

MP.write_text(m)
print("done")
