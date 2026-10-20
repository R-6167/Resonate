#!/usr/bin/env python3
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]

# --- player_screen.dart ---
p = ROOT / "lib/screens/player_screen.dart"
t = p.read_text()
if "resonate_mode_chip.dart" not in t:
    t = t.replace(
        "import '../widgets/dj_mode_status_chip.dart';\n",
        "import '../widgets/dj_mode_status_chip.dart';\n"
        "import '../widgets/resonate_mode_chip.dart';\n",
        1,
    )

if "ResonateModeChip" not in t:
    # App bar actions: mode chip before DJ chip
    old = """      actions: [
          const DjModeStatusChip(dense: true),
"""
    new = """      actions: [
          const ResonateModeChip(dense: true),
          const DjModeStatusChip(dense: true),
"""
    if old not in t:
        raise SystemExit("player actions marker miss")
    t = t.replace(old, new, 1)

    # Under metadata, above DJ transition chip
    if "DjTransitionReasonChip()" in t and "ResonateModeChip(dense: true),\n              const DjTransitionReasonChip" not in t:
        t = t.replace(
            "              const DjTransitionReasonChip(),\n",
            "              const ResonateModeChip(dense: true),\n"
            "              const SizedBox(height: 6),\n"
            "              const DjTransitionReasonChip(),\n",
            1,
        )
    p.write_text(t)
    print("player_screen wired")
else:
    print("player_screen already has ResonateModeChip")

# --- home_screen.dart ---
h = ROOT / "lib/screens/home_screen.dart"
t = h.read_text()
if "resonate_mode_chip.dart" not in t:
    t = t.replace(
        "import '../widgets/dj_mode_status_chip.dart';\n",
        "import '../widgets/dj_mode_status_chip.dart';\n"
        "import '../widgets/resonate_mode_chip.dart';\n",
        1,
    )

if "ResonateModeChip" not in t:
    # Now-playing card subtitle: mode + DJ
    old = """              const SizedBox(height: 4),
              const DjModeStatusChip(dense: true),
"""
    new = """              const SizedBox(height: 4),
              const Wrap(
                spacing: 4,
                runSpacing: 4,
                children: [
                  ResonateModeChip(dense: true),
                  DjModeStatusChip(dense: true),
                ],
              ),
"""
    if old not in t:
        # try alternate spacing
        if "const DjModeStatusChip(dense: true)" in t:
            t = t.replace(
                "const DjModeStatusChip(dense: true)",
                "Wrap(spacing: 4, runSpacing: 4, children: [ResonateModeChip(dense: true), DjModeStatusChip(dense: true)])",
                1,
            )
            print("home chip via loose replace")
        else:
            raise SystemExit("home DJ chip marker miss")
    else:
        t = t.replace(old, new, 1)
        print("home_screen wired")

    # Optional: actions on glass scaffold if present
    if "title: const ResonateLogo" in t and "ResonateModeChip" in t:
        # add actions row if scaffold has no actions yet
        if "title: const ResonateLogo(size: 48),\n      body:" in t:
            t = t.replace(
                "title: const ResonateLogo(size: 48),\n      body:",
                "title: const ResonateLogo(size: 48),\n"
                "      actions: const [ResonateModeChip(dense: true)],\n"
                "      body:",
                1,
            )
            print("home app bar actions added")
    h.write_text(t)
else:
    print("home already has ResonateModeChip")

# docs note
doc = ROOT / "docs/MODES.md"
if doc.exists():
    d = doc.read_text()
    if "Mode chip on Now Playing" not in d:
        d = d.replace(
            "| Settings → Playback → Modes screen | Present |\n",
            "| Settings → Playback → Modes screen | Present |\n"
            "| Mode chip on Now Playing + Home | Present |\n",
            1,
        )
        d = d.replace(
            "- [ ] **Active mode chip on Now Playing / home** — users cannot see the current\n"
            "  mode without opening Settings → Modes (contrast: DJ transition reason chip).\n",
            "- [x] **Active mode chip on Now Playing / home** — `ResonateModeChip`; tap opens Modes.\n",
            1,
        )
        doc.write_text(d)
        print("docs updated")

print("done")
