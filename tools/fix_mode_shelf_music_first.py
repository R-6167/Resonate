#!/usr/bin/env python3
from pathlib import Path

p = Path(__file__).resolve().parents[1] / "lib/services/mode_shelf_builder.dart"
t = p.read_text()

old = """      if (!modes.isAcceptableForAutopilot(item)) continue;
      if (preferred.isEmpty) continue; // music-first modes without prefs: folders only

      if (modes.isPreferredContent(item)) {
        fromClassifier.add(song);
      }
    }
"""

new = """      if (!modes.isAcceptableForAutopilot(item)) continue;

      if (preferred.isEmpty) {
        // Music-first modes (Running / Driving / Work): soft shelf from library.
        fromClassifier.add(song);
        continue;
      }

      if (modes.isPreferredContent(item)) {
        fromClassifier.add(song);
      }
    }

    // Prefer newer library items for music-first soft shelves.
    if (preferred.isEmpty && fromClassifier.isNotEmpty) {
      fromClassifier.sort((a, b) => b.dateAdded.compareTo(a.dateAdded));
    }
"""

if old not in t:
    raise SystemExit("classifier block miss")
t = t.replace(old, new, 1)
p.write_text(t)
print("music-first shelf ok")
