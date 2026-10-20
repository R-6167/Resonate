#!/usr/bin/env python3
from pathlib import Path
import base64, sys, zlib
ROOT = Path(__file__).resolve().parents[1]
TARGET = ROOT / "lib/providers/music_provider.dart"
def main():
    text = TARGET.read_text() if TARGET.exists() else ""
    if "_softFadeOutActive" in text and "crossfade_aborted_too_late" in text and "volumeStuckHits" in text:
        print("already present"); return 0
    chunks = sorted(ROOT.glob("tools/xfade_c*.b64"))
    if not chunks:
        print("no chunks"); return 1
    blob = "".join(p.read_text().strip() for p in chunks)
    raw = zlib.decompress(base64.b64decode(blob))
    decoded = raw.decode("utf-8")
    assert "MusicProvider" in decoded
    TARGET.write_text(decoded)
    print("wrote", TARGET.stat().st_size); return 0
if __name__ == "__main__":
    raise SystemExit(main())
