#!/usr/bin/env python3
from pathlib import Path

MP = Path("lib/providers/music_provider.dart")
m = MP.read_text()

if "await _engageDjTransitionSfx();" in m:
    print("engage already")
else:
    old = """      await _prepareDjHandoff(
        outgoing: outgoing,
        incoming: incoming,
        outgoingSong: outgoingSong,
        incomingSong: nextSong,
      );
      // Fire-and-poll play on B"""
    new = """      await _prepareDjHandoff(
        outgoing: outgoing,
        incoming: incoming,
        outgoingSong: outgoingSong,
        incomingSong: nextSong,
      );
      await _engageDjTransitionSfx();
      // Fire-and-poll play on B"""
    if old not in m:
        # try looser
        needle = "await _prepareDjHandoff("
        idx = m.find(needle)
        if idx < 0:
            raise SystemExit("prepare not found")
        # find end of this call
        end = m.find(");", idx)
        if end < 0:
            raise SystemExit("prepare end miss")
        end += 2
        m = m[:end] + "\n      await _engageDjTransitionSfx();" + m[end:]
        print("engage inserted loose")
    else:
        m = m.replace(old, new, 1)
        print("engage inserted")

if "await _restoreDjTransitionSfx();" not in m:
    old = "      // Guarantee silence on outgoing before pause/stop"
    if old in m:
        m = m.replace(old, "      await _restoreDjTransitionSfx();\n" + old, 1)
        print("restore inserted")
    else:
        print("WARN restore anchor miss")
else:
    print("restore already")

# Abort paths that return false after prepare should restore
count = m.count("await _restoreDjTransitionSfx();")
print("restore count", count)

MP.write_text(m)
print("done")
