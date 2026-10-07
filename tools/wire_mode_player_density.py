#!/usr/bin/env python3
"""Wire ModePlayerDensity into player_screen.dart (actual layout)."""
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
p = ROOT / "lib/screens/player_screen.dart"
t = p.read_text()

if "mode_player_density.dart" not in t:
    if "import '../widgets/resonate_mode_chip.dart';" in t:
        t = t.replace(
            "import '../widgets/resonate_mode_chip.dart';\n",
            "import '../widgets/resonate_mode_chip.dart';\n"
            "import '../widgets/mode_player_density.dart';\n"
            "import '../modes/providers/mode_provider.dart';\n",
            1,
        )
    elif "import '../widgets/dj_mode_status_chip.dart';" in t:
        t = t.replace(
            "import '../widgets/dj_mode_status_chip.dart';\n",
            "import '../widgets/dj_mode_status_chip.dart';\n"
            "import '../widgets/mode_player_density.dart';\n"
            "import '../modes/providers/mode_provider.dart';\n",
            1,
        )
    else:
        raise SystemExit("no import anchor")

if "Consumer2<MusicProvider, ModeProvider>" not in t:
    t = t.replace(
        "      body: Consumer<MusicProvider>(\n        builder: (context, music, _) {",
        "      body: Consumer2<MusicProvider, ModeProvider>(\n        builder: (context, music, modes, _) {",
        1,
    )
    marker = (
        "          final song = music.currentSong;\n"
        "          if (song == null) {\n"
        "            return _PlayerEmptyState();\n"
        "          }\n"
    )
    if marker not in t:
        raise SystemExit("song null marker miss")
    t = t.replace(
        marker,
        marker + "\n          final density = ModePlayerDensity.fromMode(modes);\n",
        1,
    )
    print("Consumer2 + density")

# Swipe gate
old_swipe = (
    "              GestureDetector(\n"
    "                onHorizontalDragEnd: (details) {\n"
    "                  final v = details.primaryVelocity ?? 0;\n"
    "                  if (v < -400) {\n"
    "                    music.nextSong(source: 'player_swipe');\n"
    "                  } else if (v > 400) {\n"
    "                    music.previousSong(source: 'player_swipe');\n"
    "                  }\n"
    "                },\n"
)
new_swipe = (
    "              GestureDetector(\n"
    "                onHorizontalDragEnd: density.allowHorizontalSwipe\n"
    "                    ? (details) {\n"
    "                        final v = details.primaryVelocity ?? 0;\n"
    "                        if (v < -400) {\n"
    "                          music.nextSong(source: 'player_swipe');\n"
    "                        } else if (v > 400) {\n"
    "                          music.previousSong(source: 'player_swipe');\n"
    "                        }\n"
    "                      }\n"
    "                    : null,\n"
)
if old_swipe in t:
    t = t.replace(old_swipe, new_swipe, 1)
    print("swipe gated")
else:
    print("WARN swipe pattern")

if "height: 250," in t and "density.artworkHeight" not in t:
    t = t.replace("height: 250,", "height: density.artworkHeight,", 1)
    print("artwork height")

if "density.hintLabel" not in t and "DjTransitionReasonChip" in t:
    t = t.replace(
        "              const DjTransitionReasonChip(),\n",
        "              const DjTransitionReasonChip(),\n"
        "              if (density.hintLabel != null) ...[\n"
        "                const SizedBox(height: 6),\n"
        "                Text(\n"
        "                  density.hintLabel!,\n"
        "                  textAlign: TextAlign.center,\n"
        "                  style: Theme.of(context).textTheme.labelMedium?.copyWith(\n"
        "                    color: Theme.of(context).colorScheme.tertiary,\n"
        "                    fontWeight: FontWeight.w600,\n"
        "                  ),\n"
        "                ),\n"
        "              ],\n",
        1,
    )
    print("hint")

# Transport icon sizes
if "iconSize: 36," in t and "density.transportIconSize" not in t:
    t = t.replace("iconSize: 36,", "iconSize: density.transportIconSize,", 2)
    print("prev/next iconSize")
if "iconSize: 30," in t and "density.secondaryIconSize" not in t:
    # ±10 buttons use secondary size slightly smaller than main
    t = t.replace(
        "iconSize: 30,",
        "iconSize: density.largeControls ? density.transportIconSize - 6 : 30,",
        2,
    )
    print("seek10 iconSize")

# Play FilledButton
old_play = (
    "                      FilledButton(\n"
    "                        onPressed: () {\n"
    "                          music.togglePlayPause();\n"
    "                        },\n"
    "                        child: Icon(\n"
    "                          playing\n"
    "                              ? Icons.pause_rounded\n"
    "                              : Icons.play_arrow_rounded,\n"
    "                        ),\n"
    "                      ),\n"
)
new_play = (
    "                      FilledButton(\n"
    "                        onPressed: () {\n"
    "                          music.togglePlayPause();\n"
    "                        },\n"
    "                        style: FilledButton.styleFrom(\n"
    "                          minimumSize: Size(\n"
    "                            density.playButtonSize,\n"
    "                            density.playButtonSize,\n"
    "                          ),\n"
    "                          maximumSize: Size(\n"
    "                            density.playButtonSize,\n"
    "                            density.playButtonSize,\n"
    "                          ),\n"
    "                          padding: EdgeInsets.zero,\n"
    "                          shape: const CircleBorder(),\n"
    "                        ),\n"
    "                        child: Icon(\n"
    "                          playing\n"
    "                              ? Icons.pause_rounded\n"
    "                              : Icons.play_arrow_rounded,\n"
    "                          size: density.playIconSize,\n"
    "                        ),\n"
    "                      ),\n"
)
if old_play in t:
    t = t.replace(old_play, new_play, 1)
    print("play button density")
else:
    print("WARN play button")

# Secondary chrome: volume/shuffle/repeat/queue/more
if "density.showSecondaryRow" not in t and "ResonateGlassCard(" in t:
    marker = (
        "              ResonateGlassCard(\n"
        "                padding: EdgeInsets.zero,\n"
        "                child: Padding(\n"
        "                  padding:\n"
        "                      const EdgeInsets.symmetric(horizontal: 8, vertical: 4),\n"
        "                  child: Row(\n"
        "                    mainAxisAlignment: MainAxisAlignment.spaceAround,\n"
        "                    children: [\n"
        "                      IconButton(\n"
        "                        tooltip: 'Volume',\n"
    )
    if marker in t:
        t = t.replace(
            marker,
            "              if (density.showSecondaryRow)\n" + marker,
            1,
        )
        print("secondary gated")
    else:
        print("WARN secondary")

# Intelligence / autopilot cards
if "density.showIntelligenceCards" not in t:
    intel = "              Consumer<IntelligenceProvider>("
    if intel in t:
        t = t.replace(
            intel,
            "              if (density.showIntelligenceCards)\n" + intel,
            1,
        )
        print("intelligence gated")

p.write_text(t)

# sanity
assert "ModePlayerDensity" in t
assert "Consumer2<MusicProvider, ModeProvider>" in t
print("player density OK", t.count("density."))

doc = ROOT / "docs/MODES.md"
if doc.exists():
    d = doc.read_text()
    d = d.replace(
        "- [ ] **`uiDensity` enforcement**",
        "- [x] **`uiDensity` enforcement** (player transport + chrome)",
        1,
    )
    if "Mode-aware player density" not in d:
        d = d.replace(
            "| Driving suggestion banner on Home | Present |\n",
            "| Driving suggestion banner on Home | Present |\n"
            "| Mode-aware player density | Present |\n",
            1,
        )
    doc.write_text(d)
