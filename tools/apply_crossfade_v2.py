#!/usr/bin/env python3
"""Restore + write dual-engine crossfade harden for music_provider.dart."""
from pathlib import Path
import base64
import subprocess
import sys
import zlib

ROOT = Path(__file__).resolve().parents[1]
TARGET = ROOT / "lib/providers/music_provider.dart"
PAYLOAD = ROOT / "tools/music_provider_xfade.b64"

def main() -> int:
    text = TARGET.read_text() if TARGET.exists() else ""
    if "_softFadeOutActive" in text and "crossfade_aborted_too_late" in text and "volumeStuckHits" in text:
        print("crossfade harden v2 already present")
        return 0
    if not PAYLOAD.exists():
        print("missing payload", PAYLOAD)
        return 1
    raw = zlib.decompress(base64.b64decode(PAYLOAD.read_text().strip()))
    decoded = raw.decode("utf-8")
    if "MusicProvider" not in decoded or "_performTrueCrossfade" not in decoded:
        print("payload invalid")
        return 2
    TARGET.write_text(decoded)
    print("wrote crossfade harden v2", TARGET.stat().st_size, "bytes")
    return 0

if __name__ == "__main__":
    raise SystemExit(main())
