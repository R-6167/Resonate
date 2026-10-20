#!/usr/bin/env python3
from pathlib import Path

MP = Path("lib/providers/music_provider.dart")
t = MP.read_text()

if "planDjTransitionLearned" in t:
    print("already")
    raise SystemExit(0)

old = """      final plan = planDjTransition(
        analysisA: analysisA,
        analysisB: analysisB,
        tempoMatchActive: _djTempoMatchActive,
        beatAlignActive: _djBeatAlignActive,
        maxStretchPercent: _djMaxStretchPercent,
      );
"""
new = """      final plan = await planDjTransitionLearned(
        analysisA: analysisA,
        analysisB: analysisB,
        tempoMatchActive: _djTempoMatchActive,
        beatAlignActive: _djBeatAlignActive,
        maxStretchPercent: _djMaxStretchPercent,
        fromSongId: outgoingSong.id,
        toSongId: incomingSong.id,
      );
"""
if old in t:
    MP.write_text(t.replace(old, new, 1))
    print("wired learned planner")
else:
    print("MISS")
    raise SystemExit(1)
