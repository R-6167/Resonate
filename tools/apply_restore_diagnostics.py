#!/usr/bin/env python3
from pathlib import Path
import base64
ROOT = Path(__file__).resolve().parents[1]
b64_path = ROOT / "tools/diag_full.b64"
if not b64_path.exists():
    parts = sorted(ROOT.glob("tools/diag_b64_*.txt"))
    data = "".join(p.read_text().strip() for p in parts)
else:
    data = b64_path.read_text().strip()
raw = base64.b64decode(data)
out = ROOT / "lib/services/resonate_diagnostics.dart"
out.write_bytes(raw)
print("restored", out.stat().st_size)
