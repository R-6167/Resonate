#!/usr/bin/env python3
from pathlib import Path
import base64, zlib
ROOT = Path(__file__).resolve().parents[1]
TARGET = ROOT / "lib/providers/music_provider.dart"
def main():
    t = TARGET.read_text() if TARGET.exists() else ""
    if "_prepareDjHandoff" in t and "_djTempoMatchActive" in t and "computeTempoStretch" in t:
        print("step3 already"); return 0
    a = ROOT / "tools/s3_all_a.b64"
    b = ROOT / "tools/s3_all_b.b64"
    if a.exists() and b.exists():
        blob = "".join(a.read_text().split()) + "".join(b.read_text().split())
    elif (ROOT / "tools/s3_all.b64").exists():
        blob = "".join((ROOT / "tools/s3_all.b64").read_text().split())
    else:
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
