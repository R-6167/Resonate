#!/usr/bin/env python3
from pathlib import Path

MP = Path("lib/providers/music_provider.dart")
m = MP.read_text()
if "outgoingPositionMs:" in m and "outPos" in m:
    print("already")
    raise SystemExit(0)

# Flexible: insert before planDjTransitionLearned call
needle = "      final plan = await planDjTransitionLearned("
if needle not in m:
    raise SystemExit("needle miss")

# Only if not already preceded by outPos
idx = m.find(needle)
pre = m[max(0, idx - 200):idx]
if "outPos" in pre:
    print("already near")
    raise SystemExit(0)

insert = """      final outPos = outgoing.position.inMilliseconds;
      final outDur = outgoingSong.duration.inMilliseconds > 0
          ? outgoingSong.duration.inMilliseconds
          : analysisA.durationMs;
"""
m = m[:idx] + insert + m[idx:]

# Add named args before closing of the call
old_args = """        fromSongId: outgoingSong.id,
        toSongId: incomingSong.id,
      );"""
new_args = """        fromSongId: outgoingSong.id,
        toSongId: incomingSong.id,
        outgoingPositionMs: outPos,
        outgoingDurationMs: outDur,
      );"""
if old_args not in m:
    raise SystemExit("args miss")
m = m.replace(old_args, new_args, 1)
MP.write_text(m)
print("position wired")
