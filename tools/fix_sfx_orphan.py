#!/usr/bin/env python3
from pathlib import Path

path = Path(__file__).resolve().parents[1] / "lib/services/dj_sfx_rack.dart"
t = path.read_text()
start = t.find("\n) {\n    DjSection? section;")
end = t.find("\n  List<int> _buildPhraseAnchors")
if start < 0 or end < 0 or end <= start:
    if ") {\n    DjSection? section;" not in t:
        print("already fixed")
    else:
        raise SystemExit(f"miss start={start} end={end}")
else:
    path.write_text(t[:start] + t[end:])
    print("orphan removed", end - start, "chars")
