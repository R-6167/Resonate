#!/usr/bin/env python3
from pathlib import Path
import base64, zlib
ROOT = Path(__file__).resolve().parents[1]
TARGET = ROOT / "lib/providers/music_provider.dart"
def main():
    t = TARGET.read_text() if TARGET.exists() else ""
    if "_prepareDjHandoff" in t and "_djTempoMatchActive" in t and "computeTempoStretch" in t:
        print("step3 already"); return 0
    parts = sorted(ROOT.glob("tools/s3_p*.txt"))
    if not parts:
        print("no parts"); return 1
    blob = "".join("".join(p.read_text().split()) for p in parts)
    data = zlib.decompress(base64.b64decode(blob)).decode()
    assert "_prepareDjHandoff" in data and "computeTempoStretch" in data
    TARGET.write_text(data)
    print("wrote", TARGET.stat().st_size); return 0
if __name__ == "__main__":
    raise SystemExit(main())
