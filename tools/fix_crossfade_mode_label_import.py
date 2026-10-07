#!/usr/bin/env python3
from pathlib import Path
p = Path(__file__).resolve().parents[1] / "lib/screens/crossfade_screen.dart"
t = p.read_text()
if "resonate_mode.dart" not in t:
    t = t.replace(
        "import '../modes/providers/mode_provider.dart';\n",
        "import '../modes/providers/mode_provider.dart';\n"
        "import '../modes/models/resonate_mode.dart';\n",
        1,
    )
    p.write_text(t)
    print("imported")
else:
    print("already")
