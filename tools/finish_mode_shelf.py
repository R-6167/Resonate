#!/usr/bin/env python3
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]

# Mode shelf card — See all + open full screen
card = ROOT / "lib/widgets/mode_shelf_card.dart"
t = card.read_text()
if "mode_shelf_screen.dart" not in t:
    t = t.replace(
        "import '../services/mode_shelf_builder.dart';\n",
        "import '../services/mode_shelf_builder.dart';\n"
        "import '../screens/mode_shelf_screen.dart';\n",
        1,
    )

if "See all" not in t and "ModeShelfScreen" not in t:
    # After Queue all button row, add See all
    old = """                      OutlinedButton.icon(
                        onPressed: () async {
                          final music = context.read<MusicProvider>();
                          final ok = await music.enqueueSongs(tracks);
                          if (context.mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                content: Text(
                                  ok
                                      ? 'Added ${tracks.length} track(s) to queue'
                                      : 'Nothing new to add',
                                ),
                              ),
                            );
                          }
                        },
                        icon: const Icon(Icons.queue_music_rounded),
                        label: const Text('Queue all'),
                      ),
                    ],
                  ),
"""
    new = """                      OutlinedButton.icon(
                        onPressed: () async {
                          final music = context.read<MusicProvider>();
                          final ok = await music.enqueueSongs(tracks);
                          if (context.mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                content: Text(
                                  ok
                                      ? 'Added ${tracks.length} track(s) to queue'
                                      : 'Nothing new to add',
                                ),
                              ),
                            );
                          }
                        },
                        icon: const Icon(Icons.queue_music_rounded),
                        label: const Text('Queue all'),
                      ),
                      const SizedBox(width: 8),
                      TextButton(
                        onPressed: () {
                          Navigator.of(context).push(
                            MaterialPageRoute<
                                void>(
                              builder: (_) => const ModeShelfScreen(),
                            ),
                          );
                        },
                        child: const Text('See all'),
                      ),
                    ],
                  ),
"""
    if old in t:
        t = t.replace(old, new, 1)
        print("card See all")
    else:
        # softer: title row add trailing see all when tracks non-empty
        if "ModeShelfScreen" not in t:
            t = t.replace(
                "icon: const Icon(Icons.tune_rounded),\n                    ),\n                  ],\n                ),",
                "icon: const Icon(Icons.tune_rounded),\n                    ),\n                    if (tracks.isNotEmpty)\n                      IconButton(\n                        tooltip: 'See all',\n                        icon: const Icon(Icons.list_rounded),\n                        onPressed: () {\n                          Navigator.of(context).push(\n                            MaterialPageRoute<void>(\n                              builder: (_) => const ModeShelfScreen(),\n                            ),\n                          );\n                        },\n                      ),\n                  ],\n                ),",
                1,
            )
            print("card list icon")
    card.write_text(t)

# Modes screen — open shelf button
ms = ROOT / "lib/modes/screens/modes_screen.dart"
mt = ms.read_text()
if "ModeShelfScreen" not in mt:
    if "import 'package:flutter/material.dart';" in mt:
        mt = mt.replace(
            "import 'package:flutter/material.dart';\n",
            "import 'package:flutter/material.dart';\n"
            "import '../../screens/mode_shelf_screen.dart';\n",
            1,
        )
    # After mode chips / near top of body column
    if "'Content folders'" in mt or 'Content folders' in mt:
        # insert before content folders section
        needle = "'Content folders'"
        idx = mt.find(needle)
        # find a widget start before - insert a ListTile for shelf
        insert = """
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.playlist_play_rounded),
            title: const Text('Mode shelf'),
            subtitle: const Text(
              'Virtual playlist from folders and mode matches — does not hide your library',
            ),
            trailing: const Icon(Icons.chevron_right_rounded),
            onTap: () {
              Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => const ModeShelfScreen(),
                ),
              );
            },
          ),
          const SizedBox(height: 12),
"""
        # Find the Text widget containing Content folders
        pos = mt.find("Content folders")
        if pos > 0:
            # go back to start of that widget line
            line_start = mt.rfind("\n", 0, pos)
            mt = mt[: line_start + 1] + insert + mt[line_start + 1 :]
            print("modes shelf link")
    ms.write_text(mt)
else:
    print("modes already has shelf")

# Player — secondary or under mode chip open shelf
player = ROOT / "lib/screens/player_screen.dart"
pt = player.read_text()
if "ModeShelfScreen" not in pt and "mode_shelf_screen.dart" not in pt:
    pt = pt.replace(
        "import '../widgets/mode_player_density.dart';\n",
        "import '../widgets/mode_player_density.dart';\n"
        "import 'mode_shelf_screen.dart';\n",
        1,
    )
    # After density hint, add open shelf when not normal
    if "density.hintLabel != null" in pt and "ModeShelfScreen" not in pt:
        old = """              if (density.hintLabel != null) ...[
                const SizedBox(height: 6),
                Text(
                  density.hintLabel!,
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.labelMedium?.copyWith(
                    color: Theme.of(context).colorScheme.tertiary,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
"""
        # match actual indentation from file
        if old not in pt:
            # try without exact spaces
            import re

            m = re.search(
                r"if \(density\.hintLabel != null\) \.\.\.\[(.*?)\],\n",
                pt,
                re.S,
            )
            if m:
                block = m.group(0)
                pt = pt.replace(
                    block,
                    block
                    + "              if (density.mode != null && modes.mode.name != 'normal')\n"
                    "                TextButton.icon(\n"
                    "                  onPressed: () {\n"
                    "                    Navigator.of(context).push(\n"
                    "                      MaterialPageRoute<void>(\n"
                    "                        builder: (_) => const ModeShelfScreen(),\n"
                    "                      ),\n"
                    "                    );\n"
                    "                  },\n"
                    "                  icon: const Icon(Icons.playlist_play_rounded, size: 18),\n"
                    "                  label: const Text('Mode shelf'),\n"
                    "                ),\n",
                    1,
                )
                print("player shelf button")
            else:
                print("WARN player hint block")
        else:
            pt = pt.replace(
                old,
                old
                + "              if (modes.mode.name != 'normal')\n"
                "                TextButton.icon(\n"
                "                  onPressed: () {\n"
                "                    Navigator.of(context).push(\n"
                "                      MaterialPageRoute<void>(\n"
                "                        builder: (_) => const ModeShelfScreen(),\n"
                "                      ),\n"
                "                    );\n"
                "                  },\n"
                "                  icon: const Icon(Icons.playlist_play_rounded, size: 18),\n"
                "                  label: const Text('Mode shelf'),\n"
                "                ),\n",
                1,
            )
            print("player shelf button exact")
    player.write_text(pt)

doc = ROOT / "docs/MODES.md"
if doc.exists():
    d = doc.read_text()
    if "ModeShelfScreen" not in d:
        d = d.replace(
            "| Mode shelf (virtual playlist on Home) | Present |\n",
            "| Mode shelf (virtual playlist on Home) | Present |\n"
            "| Mode shelf full screen (See all) | Present |\n",
            1,
        )
        doc.write_text(d)

print("finish shelf done")
