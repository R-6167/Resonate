#!/usr/bin/env python3
from pathlib import Path
import re
import sys
ROOT = Path(__file__).resolve().parents[1]
TARGET = ROOT / "lib/providers/music_provider.dart"

def main() -> int:
    if not TARGET.exists():
        print("missing", TARGET); return 1
    text = TARGET.read_text()
    if "_softFadeOutActive" in text and "crossfade_aborted_too_late" in text:
        print("already present"); return 0

    m = re.search(r"  void _maybeStartAutomaticCrossfade\(Duration position\) \{.*?\n  \}\n", text, re.S)
    if not m:
        print("maybe block not found"); return 2
    new_maybe = Path(__file__).with_name("xfade_maybe.txt").read_text()
    text = text[:m.start()] + new_maybe + "\n" + text[m.end():]

    start = text.find("  Future<void> _runAutomaticCrossfade() async {")
    end = text.find("  /// Safety net: if the player sits at the end of a track without advancing,")
    if start < 0 or end < 0:
        print("run block not found"); return 3
    new_run = Path(__file__).with_name("xfade_run.txt").read_text()
    text = text[:start] + new_run + text[end:]

    for name in ("xfade_remaining.txt", "xfade_poll.txt", "xfade_fire.txt", "xfade_silence.txt"):
        pair = Path(__file__).with_name(name).read_text().split("\n---SPLIT---\n", 1)
        if len(pair) != 2:
            print("bad pair", name); return 4
        old, new = pair
        if old not in text:
            print("block not found", name); return 5
        text = text.replace(old, new, 1)

    if "_softFadeOutActive" not in text or "crossfade_aborted_too_late" not in text:
        print("markers missing"); return 8
    TARGET.write_text(text)
    print("applied", TARGET.stat().st_size); return 0

if __name__ == "__main__":
    raise SystemExit(main())
