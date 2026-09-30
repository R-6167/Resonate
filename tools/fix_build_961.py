#!/usr/bin/env python3
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]

# 1) Autopilot: import ResonateMode extension or use .name
ap = ROOT / "lib/providers/autopilot_controller.dart"
t = ap.read_text()
if "resonate_mode.dart" not in t:
    t = t.replace(
        "import 'mode_provider.dart';\n",
        "import 'mode_provider.dart';\nimport '../models/resonate_mode.dart';\n",
        1,
    )
    print("autopilot: imported resonate_mode")
# safer diagnostic string uses extension after import
if "modes?.mode.id" in t:
    # keep .id once extension is imported
    print("autopilot: mode.id ok with import")
ap.write_text(t)

# 2) Player: wrong getter name
pl = ROOT / "lib/screens/player_screen.dart"
pt = pl.read_text()
if "canResumeCurrentQueueSong" in pt:
    pt = pt.replace("canResumeCurrentQueueSong", "canContinueListening")
    pl.write_text(pt)
    print("player: canContinueListening")
elif "canContinueListening" in pt:
    print("player: already correct")
else:
    print("player: no resume chip reference")

print("build 961 fixes done")
