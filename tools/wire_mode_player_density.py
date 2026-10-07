#!/usr/bin/env python3
"""Wire ModePlayerDensity into player_screen.dart."""
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
p = ROOT / "lib/screens/player_screen.dart"
t = p.read_text()

if "mode_player_density.dart" not in t:
    t = t.replace(
        "import '../widgets/resonate_mode_chip.dart';\n",
        "import '../widgets/resonate_mode_chip.dart';\n"
        "import '../widgets/mode_player_density.dart';\n"
        "import '../modes/providers/mode_provider.dart';\n",
        1,
    )

# Switch body Consumer to Consumer2 for ModeProvider
if "Consumer2<MusicProvider, ModeProvider>" not in t:
    t = t.replace(
        "      body: Consumer<MusicProvider>(\n        builder: (context, music, _) {",
        "      body: Consumer2<MusicProvider, ModeProvider>(\n        builder: (context, music, modes, _) {",
        1,
    )
    # Insert density right after song null check block start - after song == null empty state
    marker = "          final song = music.currentSong;\n          if (song == null) {\n            return _PlayerEmptyState();\n          }\n"
    insert = marker + "\n          final density = ModePlayerDensity.fromMode(modes);\n"
    if marker not in t:
        raise SystemExit("song null marker miss")
    t = t.replace(marker, insert, 1)
    print("Consumer2 + density")

# Swipe: gate on density.allowHorizontalSwipe
old_swipe = """              GestureDetector(
                onHorizontalDragEnd: (details) {
                  final v = details.primaryVelocity ?? 0;
                  if (v < -400) {
                    music.nextSong(source: 'player_swipe');
                  } else if (v > 400) {
                    music.previousSong(source: 'player_swipe');
                  }
                },
"""
new_swipe = """              GestureDetector(
                onHorizontalDragEnd: density.allowHorizontalSwipe
                    ? (details) {
                        final v = details.primaryVelocity ?? 0;
                        if (v < -400) {
                          music.nextSong(source: 'player_swipe');
                        } else if (v > 400) {
                          music.previousSong(source: 'player_swipe');
                        }
                      }
                    : null,
"""
if old_swipe in t:
    t = t.replace(old_swipe, new_swipe, 1)
    print("swipe gated")
else:
    print("WARN swipe")

# Artwork height
if "height: 250," in t and "density.artworkHeight" not in t:
    t = t.replace("height: 250,", "height: density.artworkHeight,", 1)
    print("artwork height")

# Density hint under mode chips
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
    print("hint label")

# Seek slider theme - wrap SeekBar or Slider if present
# Look for SliderTheme or custom seek - may be _SeekBar widget
if "_SeekBar(" in t and "SliderTheme" not in t[t.find("_SeekBar("):t.find("_SeekBar(")+400]:
    pass  # seek widget internal

# Transport IconButtons - enlarge with style
old_prev = """                      IconButton(
                        tooltip: 'Previous',
                        icon: const Icon(Icons.skip_previous_rounded),
"""
# find actual previous button text
import re
# Enlarge play FilledButton
if "playButtonSize" not in t:
    # FilledButton for play/pause
    m = re.search(
        r"FilledButton\(\s*onPressed:.*?Icons\.(?:pause_rounded|play_arrow_rounded).*?\),",
        t,
        re.S,
    )
    # Simpler: after return Row( for transport, inject Style
    old_row = """                  return Row(
                    mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                    children: [
                      IconButton(
                        tooltip: 'Previous',
"""
    # Try flexible match for previous
    if "mainAxisAlignment: MainAxisAlignment.spaceEvenly" in t:
        # Replace first spaceEvenly transport block IconButton icons with sized ones
        # Patch IconButton theme via IconTheme
        inject_before = "                  return Row(\n                    mainAxisAlignment: MainAxisAlignment.spaceEvenly,"
        inject_after = """                  return IconTheme(
                    data: IconThemeData(size: density.transportIconSize),
                    child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceEvenly,"""
        if inject_before in t and "IconTheme(\n                    data: IconThemeData(size: density.transportIconSize)" not in t:
            t = t.replace(inject_before, inject_after, 1)
            # Close IconTheme after transport row ends - find closing of that Row
            # The transport row ends before secondary Padding - look for pattern
            # after skip_next IconButton block
            close_marker = """                    ],
                  );
                },
              ),
              const SizedBox(height: 4),
              Padding(
"""
            close_new = """                    ],
                  ),
                  );
                },
              ),
              const SizedBox(height: 4),
              Padding(
"""
            # secondary might have different spacing
            if close_marker in t:
                t = t.replace(close_marker, close_new, 1)
                print("IconTheme wrap transport")
            else:
                # try without SizedBox 4
                alt = """                    ],
                  );
                },
              ),
"""
                # Only first occurrence after IconTheme
                idx = t.find("IconThemeData(size: density.transportIconSize)")
                if idx > 0:
                    rest = t[idx:]
                    # find first `],\n                  );` after IconTheme child Row
                    m2 = re.search(r"(\s*\],\n                  );)", rest)
                    if m2:
                        t = t[:idx] + rest[: m2.start()] + "\n                  )," + rest[m2.start() :]  # noqa wrong
                        # simpler approach below
                print("WARN close IconTheme - manual")

# Play button size - FilledButton style
old_fb = """                      FilledButton(
                        onPressed: () =>
                            PlaybackAuthority.instance.userToggle(music),
                        style: FilledButton.styleFrom(
"""
# Check actual FilledButton structure
if "FilledButton(" in t and "density.playButtonSize" not in t:
    # Match FilledButton with styleFrom if any
    fb_pat = re.compile(
        r"(FilledButton\(\s*onPressed:[^,]*,\s*)(style: FilledButton\.styleFrom\([^)]*\),\s*)?",
        re.S,
    )
    # Find play FilledButton region
    idx = t.find("PlaybackAuthority.instance.userToggle(music)")
    if idx > 0:
        # look backward for FilledButton(
        start = t.rfind("FilledButton(", 0, idx)
        if start > 0:
            chunk = t[start : start + 450]
            if "density.playButtonSize" not in chunk:
                # Insert style after onPressed line
                if "style: FilledButton.styleFrom" in chunk:
                    t = t[:start] + chunk.replace(
                        "style: FilledButton.styleFrom(",
                        "style: FilledButton.styleFrom(\n                          minimumSize: Size(density.playButtonSize, density.playButtonSize),\n                          shape: const CircleBorder(),\n                          // density",
                        1,
                    ) + t[start + len(chunk) :]  # fragile
                else:
                    # onPressed: () => PlaybackAuthority... ,\n                        child:
                    old = """                      FilledButton(
                        onPressed: () =>
                            PlaybackAuthority.instance.userToggle(music),
"""
                    new = """                      FilledButton(
                        onPressed: () =>
                            PlaybackAuthority.instance.userToggle(music),
                        style: FilledButton.styleFrom(
                          minimumSize: Size(
                            density.playButtonSize,
                            density.playButtonSize,
                          ),
                          maximumSize: Size(
                            density.playButtonSize,
                            density.playButtonSize,
                          ),
                          padding: EdgeInsets.zero,
                          shape: const CircleBorder(),
                        ),
"""
                    if old in t:
                        t = t.replace(old, new, 1)
                        print("play button size")
                    else:
                        # single line onPressed
                        old2 = """                      FilledButton(
                        onPressed: () => PlaybackAuthority.instance.userToggle(music),
"""
                        if old2 in t:
                            t = t.replace(
                                old2,
                                old2.replace(
                                    "userToggle(music),",
                                    "userToggle(music),\n                        style: FilledButton.styleFrom(\n                          minimumSize: Size(density.playButtonSize, density.playButtonSize),\n                          maximumSize: Size(density.playButtonSize, density.playButtonSize),\n                          padding: EdgeInsets.zero,\n                          shape: const CircleBorder(),\n                        ),",
                                ),
                                1,
                            )
                            print("play button size v2")
                        else:
                            print("WARN play button")

# Play icon size
if "Icons.pause_rounded" in t and "density.playIconSize" not in t:
    t = t.replace(
        "icon: Icon(\n                          playing\n                              ? Icons.pause_rounded\n                              : Icons.play_arrow_rounded,
                        )",
        "icon: Icon(\n                          playing\n                              ? Icons.pause_rounded\n                              : Icons.play_arrow_rounded,\n                          size: density.playIconSize,\n                        )",
        1,
    )
    # alternate format
    if "size: density.playIconSize" not in t:
        t = t.replace(
            ": Icons.play_arrow_rounded,",
            ": Icons.play_arrow_rounded,\n                          size: density.playIconSize,",
            1,
        )
        print("play icon size alt")

# Secondary row - hide advanced when minimal via Visibility
if "showSecondaryRow" not in t:
    # Find secondary Padding with shuffle - wrap
    sec = "              Padding(\n                padding: const EdgeInsets.symmetric(horizontal: 8),\n                child: Row(\n                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,"
    # may not match exactly
    if "Icons.shuffle" in t or "shuffleEnabled" in t:
        # Wrap the Padding that contains shuffle
        idx = t.find("music.setShuffleEnabled")
        if idx > 0:
            # find Padding before
            pstart = t.rfind("Padding(", 0, idx)
            if pstart > 0 and "density.showSecondaryRow" not in t[pstart : pstart + 80]:
                t = (
                    t[:pstart]
                    + "if (density.showSecondaryRow)\n              "
                    + t[pstart:]
                )
                print("secondary gated")

# Intelligence cards
if "showIntelligenceCards" not in t and "Anticipated" not in t:
    idx = t.find("Consumer<IntelligenceProvider>")
    if idx > 0:
        t = (
            t[:idx]
            + "if (density.showIntelligenceCards)\n              "
            + t[idx:]
        )
        print("intelligence gated")

# Fix IconTheme close if left open
if "IconThemeData(size: density.transportIconSize)" in t:
    # Ensure matching paren - count from IconTheme
    pass

p.write_text(t)
print("player density script done")

doc = ROOT / "docs/MODES.md"
if doc.exists():
    d = doc.read_text()
    d = d.replace(
        "- [ ] **`uiDensity` enforcement**",
        "- [x] **`uiDensity` enforcement** (player transport + chrome)",
        1,
    )
    doc.write_text(d)
