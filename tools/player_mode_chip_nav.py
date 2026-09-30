#!/usr/bin/env python3
from pathlib import Path

path = Path(__file__).resolve().parents[1] / "lib/screens/player_screen.dart"
t = path.read_text()
if "modes_screen.dart" not in t:
    t = t.replace(
        "import 'queue_screen.dart';\n",
        "import 'queue_screen.dart';\nimport 'modes_screen.dart';\n",
        1,
    )
old = """                onPressed: () {
                  // Cycle is intentional for Driving/Running quick access later;
                  // for now open is not needed — chip is informational.
                },
"""
new = """                onPressed: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(builder: (_) => const ModesScreen()),
                  );
                },
"""
if old in t:
    t = t.replace(old, new, 1)
    print("chip nav ok")
elif "ModesScreen()" in t:
    print("already navigates")
else:
    print("pattern miss")
path.write_text(t)
