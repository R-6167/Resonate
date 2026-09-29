#!/usr/bin/env python3
from pathlib import Path
import base64
ROOT = Path(__file__).resolve().parents[1]
TOOLS = Path(__file__).resolve().parent
parts = []
for i in range(8):
    p = TOOLS / f"eqglass_{i}.b64"
    if not p.exists():
        raise SystemExit(f"missing {p}")
    parts.append(p.read_text().strip())
data = base64.b64decode("".join(parts).encode())
dest = ROOT / "lib/screens/equalizer_screen.dart"
dest.write_bytes(data)
print(f"wrote equalizer_screen.dart {len(data)} bytes colour={b'Colour effects' in data}")
