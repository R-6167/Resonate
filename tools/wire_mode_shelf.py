#!/usr/bin/env python3
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
home = ROOT / "lib/screens/home_screen.dart"
t = home.read_text()

if "mode_shelf_card.dart" not in t:
    t = t.replace(
        "import '../widgets/resonate_mode_chip.dart';\n",
        "import '../widgets/resonate_mode_chip.dart';\n"
        "import '../widgets/mode_shelf_card.dart';\n",
        1,
    )

if "ModeShelfCard" not in t:
    # Insert after now-playing / early in dashboard children
    # Look for AutopilotHomeCard or EvolvingMixCard or section patterns
    markers = [
        "const AutopilotHomeCard(),",
        "AutopilotHomeCard(),",
        "const EvolvingMixCard(),",
        "EvolvingMixCard(),",
    ]
    inserted = False
    for m in markers:
        if m in t:
            t = t.replace(m, "const ModeShelfCard(),\n      " + m, 1)
            inserted = True
            print("inserted before", m)
            break
    if not inserted:
        # children.add pattern near start of dashboard
        if "children.add(" in t:
            # after first children block for now playing - add ModeShelfCard as widget in list
            needle = "final children = <Widget>["
            if needle in t:
                t = t.replace(
                    needle,
                    needle + "\n      const ModeShelfCard(),",
                    1,
                )
                print("inserted at children list")
                inserted = True
    if not inserted:
        raise SystemExit("could not find home insertion point")
    home.write_text(t)
    print("home shelf wired")
else:
    print("home already has ModeShelfCard")

# MediaFolderStore.supportedTypes - verify builder references
store = (ROOT / "lib/modes/services/media_folder_store.dart").read_text()
if "supportedTypes" in store:
    print("folder store has supportedTypes")

doc = ROOT / "docs/MODES.md"
if doc.exists():
    d = doc.read_text()
    if "Mode shelf" not in d or "Mode shelf (virtual" not in d:
        d = d.replace(
            "| Mode chip on Now Playing + Home | Present |\n",
            "| Mode chip on Now Playing + Home | Present |\n"
            "| Mode shelf (virtual playlist on Home) | Present |\n",
            1,
        )
        doc.write_text(d)
        print("docs updated")

print("done")
