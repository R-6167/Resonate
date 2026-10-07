#!/usr/bin/env python3
"""Wire intel, save-playlist, library badges, DJ soft-gate."""
from pathlib import Path
import re

ROOT = Path(__file__).resolve().parents[1]

# ---- Mode shelf screen ----
scr = ROOT / "lib/screens/mode_shelf_screen.dart"
st = scr.read_text()

if "IntelligenceProvider" not in st:
    st = st.replace(
        "import '../providers/music_provider.dart';\n",
        "import '../providers/music_provider.dart';\n"
        "import '../providers/intelligence_provider.dart';\n"
        "import '../providers/playlist_provider.dart';\n",
        1,
    )
    st = st.replace(
        "    return Consumer2<ModeProvider, LibraryProvider>(\n      builder: (context, modes, library, _) {\n        final shelf = ModeShelfBuilder.build(\n          modes: modes,\n          library: library.allSongs,\n          limit: 200,\n        );\n",
        "    return Consumer3<ModeProvider, LibraryProvider, IntelligenceProvider>(\n      builder: (context, modes, library, intel, _) {\n        final intelSongs = intel.isEnabled\n            ? intel.recommendations.map((r) => r.song).toList()\n            : const <Song>[];\n        final shelf = ModeShelfBuilder.build(\n          modes: modes,\n          library: library.allSongs,\n          intelligenceSongs: intelSongs,\n          limit: 200,\n        );\n",
        1,
    )

# Save as playlist button in actions
if "Save as playlist" not in st:
    st = st.replace(
        """          actions: [
            IconButton(
              tooltip: 'Modes',
""",
        """          actions: [
            if (!shelf.isEmpty)
              IconButton(
                tooltip: 'Save as playlist',
                icon: const Icon(Icons.playlist_add_rounded),
                onPressed: () => _saveAsPlaylist(context, shelf),
              ),
            IconButton(
              tooltip: 'Modes',
""",
        1,
    )

# Intelligence section in list
if "From Intelligence" not in st and "fromIntelligence" in st:
    old_list = """                              if (shelf.fromClassifier.isNotEmpty) ...[
                                _section(context, 'Suggested for this mode'),
                                ...shelf.fromClassifier.map(
                                  (s) => _tile(
                                    context,
                                    s,
                                    shelf.tracks,
                                    badge: 'Suggested',
                                  ),
                                ),
                              ],
"""
    new_list = """                              if (shelf.fromClassifier.isNotEmpty) ...[
                                _section(context, 'Suggested for this mode'),
                                ...shelf.fromClassifier.map(
                                  (s) => _tile(
                                    context,
                                    s,
                                    shelf.tracks,
                                    badge: 'Suggested',
                                  ),
                                ),
                              ],
                              if (shelf.fromIntelligence.isNotEmpty) ...[
                                _section(context, 'From Intelligence'),
                                ...shelf.fromIntelligence.map(
                                  (s) => _tile(
                                    context,
                                    s,
                                    shelf.tracks,
                                    badge: 'Intelligence',
                                  ),
                                ),
                              ],
"""
    if old_list in st:
        st = st.replace(old_list, new_list, 1)
        print("intel section")

# _saveAsPlaylist static method before closing class
if "_saveAsPlaylist" not in st:
    st = st.replace(
        "  static void _playShelf(",
        """  static Future<void> _saveAsPlaylist(
    BuildContext context,
    ModeShelf shelf,
  ) async {
    final name =
        '${shelf.mode.label} shelf · ${DateTime.now().month}/${DateTime.now().day}';
    final playlists = context.read<PlaylistProvider>();
    final created = await playlists.createPlaylist(
      name,
      description:
          'Saved from ${shelf.mode.label} mode shelf (folders + suggestions).',
    );
    if (created == null) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Could not create playlist')),
        );
      }
      return;
    }
    await playlists.addSongs(created.id, shelf.tracks);
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Saved ${shelf.tracks.length} tracks as "$name"',
          ),
        ),
      );
    }
  }

  static void _playShelf(",
        1,
    )
    print("save playlist")

scr.write_text(st)

# ---- Mode shelf card ----
card = ROOT / "lib/widgets/mode_shelf_card.dart"
ct = card.read_text()
if "IntelligenceProvider" not in ct:
    ct = ct.replace(
        "import '../providers/music_provider.dart';\n",
        "import '../providers/music_provider.dart';\n"
        "import '../providers/intelligence_provider.dart';\n",
        1,
    )
    ct = ct.replace(
        "    return Consumer2<ModeProvider, LibraryProvider>(\n      builder: (context, modes, library, _) {\n        if (!modes.isReady) return const SizedBox.shrink();\n\n        final shelf = ModeShelfBuilder.build(\n          modes: modes,\n          library: library.allSongs,\n        );\n",
        "    return Consumer3<ModeProvider, LibraryProvider, IntelligenceProvider>(\n      builder: (context, modes, library, intel, _) {\n        if (!modes.isReady) return const SizedBox.shrink();\n\n        final intelSongs = intel.isEnabled\n            ? intel.recommendations.map((r) => r.song).toList()\n            : const <Song>[];\n        final shelf = ModeShelfBuilder.build(\n          modes: modes,\n          library: library.allSongs,\n          intelligenceSongs: intelSongs,\n        );\n",
        1,
    )
    if "import '../models/song.dart'" not in ct:
        ct = ct.replace(
            "import 'package:flutter/material.dart';\n",
            "import 'package:flutter/material.dart';\nimport '../models/song.dart';\n",
            1,
        )
    card.write_text(ct)
    print("card intel")

# ---- Library badges ----
lib = ROOT / "lib/screens/library_screen.dart"
lt = lib.read_text()
if "mode_shelf_builder.dart" not in lt:
    lt = lt.replace(
        "import 'package:flutter/material.dart';\n",
        "import 'package:flutter/material.dart';\n"
        "import '../modes/providers/mode_provider.dart';\n"
        "import '../providers/intelligence_provider.dart';\n"
        "import '../services/mode_shelf_builder.dart';\n",
        1,
    )
if "Consumer2<LibraryProvider, MusicProvider>" in lt:
    lt = lt.replace(
        "            child: Consumer2<LibraryProvider, MusicProvider>(\n              builder: (context, library, music, _) {",
        "            child: Consumer3<LibraryProvider, MusicProvider, ModeProvider>(\n              builder: (context, library, music, modes, _) {",
        1,
    )
    # subtitle with badge
    old_sub = """                      subtitle: Text(
                        song.artist,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
"""
    new_sub = """                      subtitle: Builder(
                        builder: (context) {
                          final intel = context.watch<IntelligenceProvider>();
                          final intelSongs = intel.isEnabled
                              ? intel.recommendations.map((r) => r.song).toList()
                              : const <Song>[];
                          final badge = ModeShelfBuilder.membershipBadge(
                            modes: modes,
                            song: song,
                            library: library.allSongs,
                            intelligenceSongs: intelSongs,
                          );
                          final text = badge == null
                              ? song.artist
                              : '${song.artist} · $badge';
                          return Text(
                            text,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: badge == null
                                ? null
                                : TextStyle(
                                    color: Theme.of(context)
                                        .colorScheme
                                        .tertiary,
                                  ),
                          );
                        },
                      ),
"""
    if old_sub in lt:
        lt = lt.replace(old_sub, new_sub, 1)
        print("library badge")
    if "import '../models/song.dart'" not in lt:
        # Song may come via library provider exports - check
        if "Song" in new_sub and "models/song.dart" not in lt:
            lt = lt.replace(
                "import '../modes/providers/mode_provider.dart';\n",
                "import '../modes/providers/mode_provider.dart';\n"
                "import '../models/song.dart';\n",
                1,
            )
    lib.write_text(lt)

# ---- DJ soft-gate when mode blocks crossfade ----
mp = ROOT / "lib/providers/music_provider.dart"
mt = mp.read_text()
# Add helper after mode crossfade fields usage
if "_djHandoffsLive" not in mt:
    # Insert getter near canCrossfadeNext
    needle = "  bool get effectiveCrossfadeEnabled =>\n      _crossfadeEnabled && _modeCrossfadeAllowed;\n"
    if needle in mt:
        mt = mt.replace(
            needle,
            needle
            + "\n"
            "  /// DJ beat/tempo/SFX only apply when the mode still allows crossfade.\n"
            "  bool get _djHandoffsLive =>\n      _modeCrossfadeAllowed &&\n      (_djBeatAlignActive || _djTempoMatchActive || _djSfxActive);\n",
            1,
        )
        # Replace common djActive patterns carefully - only exact triples
        mt = mt.replace(
            "(_djBeatAlignActive || _djTempoMatchActive || _djSfxActive)",
            "_djHandoffsLive",
        )
        # dual without sfx
        mt = mt.replace(
            "(_djBeatAlignActive || _djTempoMatchActive)",
            "(_djHandoffsLive && (_djBeatAlignActive || _djTempoMatchActive))",
        )
        # Fix over-replace if _djHandoffsLive && (_djHandoffsLive
        mt = mt.replace(
            "(_djHandoffsLive && (_djHandoffsLive && (_djBeatAlignActive || _djTempoMatchActive)))",
            "(_djHandoffsLive && (_djBeatAlignActive || _djTempoMatchActive))",
        )
        print("dj soft-gate")
        mp.write_text(mt)
    else:
        print("WARN effectiveCrossfade")

# ---- docs ----
doc = ROOT / "docs/MODES.md"
if doc.exists():
    d = doc.read_text()
    block = """
## DJ Mode and Intelligence under Modes

| Layer | Podcast / Audiobook | Music modes (Normal, Running, Driving, …) |
|-------|---------------------|---------------------------------------------|
| **Crossfade** | Policy **off** (`crossfadeAllowed: false`) | Allowed when user enables Crossfade |
| **DJ Mode** | Settings can stay on, but **handoffs are soft-gated** — no beat/tempo/SFX blend while mode blocks crossfade | Full DJ when master + feature toggles on |
| **Intelligence** | Still ranks/suggests; shelf only keeps items **acceptable** for the mode (speech-biased) | Full recommendations on shelf + Autopilot bias |
| **Autopilot** | Content bias prefers mode media types | Music-first bias |

Modes never hard-disable Intelligence or DJ *settings*. They **constrain what the engine is allowed to do** so speech listening stays precise and non-bullying.

"""
    if "DJ Mode and Intelligence under Modes" not in d:
        d += block
        doc.write_text(d)

print("optional finishes done")
