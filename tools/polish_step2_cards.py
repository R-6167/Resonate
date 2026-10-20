#!/usr/bin/env python3
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]

# DJ Mode — Card with margin/elevation → glass
dj = ROOT / "lib/screens/dj_mode_settings_screen.dart"
t = dj.read_text()
old = """              Card(
                margin: EdgeInsets.zero,
                elevation: 0,
"""
new = """              ResonateGlassCard(
                margin: EdgeInsets.zero,
                padding: EdgeInsets.zero,
"""
if old in t:
    t = t.replace(old, new)
    # remove elevation-only leftover if any (already stripped)
    dj.write_text(t)
    print("dj cards -> glass", t.count("ResonateGlassCard"))
else:
    print("dj: pattern missing or already done")

intel = ROOT / "lib/screens/intelligence_settings_screen.dart"
t = intel.read_text()
old = """        Card(
          margin: const EdgeInsets.fromLTRB(16, 8, 16, 8),
          child: Padding(
"""
new = """        ResonateGlassCard(
          margin: const EdgeInsets.fromLTRB(16, 8, 16, 8),
          padding: EdgeInsets.zero,
          child: Padding(
"""
if old in t:
    t = t.replace(old, new)
    intel.write_text(t)
    print("intel cards -> glass", t.count("ResonateGlassCard"))
else:
    print("intel: pattern missing or already done")

# Any remaining bare Card( in these two files → glass with zero padding
for path in (dj, intel):
    t = path.read_text()
    if "\n        Card(" in t or "\n              Card(" in t:
        t2 = t.replace("\n              Card(", "\n              ResonateGlassCard(\n                padding: EdgeInsets.zero,")
        t2 = t2.replace("\n        Card(", "\n        ResonateGlassCard(\n          padding: EdgeInsets.zero,")
        if t2 != t:
            path.write_text(t2)
            print(path.name, "extra Card sweep")
print("done")
