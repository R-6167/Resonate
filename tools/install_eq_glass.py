#!/usr/bin/env python3
import base64, zlib, sys
from pathlib import Path
ns1, ns2 = {}, {}
base = Path(__file__).resolve().parent
exec((base / "eq_glass_b1.py").read_text(), ns1)
exec((base / "eq_glass_b2.py").read_text(), ns2)
data = zlib.decompress(base64.b64decode((ns1["B1"] + ns2["B2"]).encode()))
dest = Path(__file__).resolve().parents[1] / "lib/screens/equalizer_screen.dart"
dest.write_bytes(data)
print("wrote", len(data), "colour", b"Colour effects" in data)
