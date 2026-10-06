#!/usr/bin/env python3
from pathlib import Path

root = Path(__file__).resolve().parents[1] / "test" / "modes"
n = 0
for p in root.glob("*.dart"):
    t = p.read_text()
    nt = t.replace("package:resonate_modes_lab/", "package:resonate/")
    if nt != t:
        p.write_text(nt)
        n += 1
        print("fixed", p.name)
print("files", n)
