#!/usr/bin/env python3
"""Remove invalid named args on ResonateGlassCard (color/elevation)."""
from pathlib import Path
import re

ROOT = Path(__file__).resolve().parents[1]

TARGETS = [
    "lib/screens/dj_mode_settings_screen.dart",
    "lib/screens/player_screen.dart",
]

# Lines that are only color: ... or elevation: ... under GlassCard
line_re = re.compile(
    r"^(\s*)(color|elevation):\s*.*,\s*$"
)

for rel in TARGETS:
    path = ROOT / rel
    if not path.exists():
        print("missing", rel)
        continue
    lines = path.read_text().splitlines(keepends=True)
    out = []
    i = 0
    changed = 0
    while i < len(lines):
        line = lines[i]
        # When we see ResonateGlassCard(, strip following invalid named params until child:
        if "ResonateGlassCard(" in line:
            out.append(line)
            i += 1
            while i < len(lines):
                cur = lines[i]
                stripped = cur.lstrip()
                # stop at child: or other valid props we keep
                if stripped.startswith("child:"):
                    out.append(cur)
                    i += 1
                    break
                if stripped.startswith("padding:") or stripped.startswith("margin:") or stripped.startswith("borderRadius:") or stripped.startswith("key:"):
                    out.append(cur)
                    i += 1
                    continue
                if stripped.startswith("color:") or stripped.startswith("elevation:"):
                    changed += 1
                    i += 1
                    continue
                # unknown line inside ctor — keep
                out.append(cur)
                i += 1
            continue
        out.append(line)
        i += 1
    if changed:
        path.write_text("".join(out))
        print(f"{rel}: removed {changed} invalid arg line(s)")
    else:
        print(f"{rel}: no invalid color/elevation lines")

print("done")
