#!/usr/bin/env python3
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]

# Mode shelf card — intelligence
card = ROOT / "lib/widgets/mode_shelf_card.dart"
if card.exists():
    ct = card.read_text()
    if "IntelligenceProvider" not in ct:
        if "import '../providers/music_provider.dart';" in ct:
            ct = ct.replace(
                "import '../providers/music_provider.dart';\n",
                "import '../providers/music_provider.dart';\n"
                "import '../providers/intelligence_provider.dart';\n"
                "import '../models/song.dart';\n",
                1,
            )
        ct = ct.replace(
            "Consumer2<ModeProvider, LibraryProvider>",
            "Consumer3<ModeProvider, LibraryProvider, IntelligenceProvider>",
            1,
        )
        ct = ct.replace(
            "builder: (context, modes, library, _) {",
            "builder: (context, modes, library, intel, _) {",
            1,
        )
        old = """        final shelf = ModeShelfBuilder.build(
          modes: modes,
          library: library.allSongs,
        );
"""
        new = """        final intelSongs = intel.isEnabled
            ? intel.recommendations.map((r) => r.song).toList()
            : const <Song>[];
        final shelf = ModeShelfBuilder.build(
          modes: modes,
          library: library.allSongs,
          intelligenceSongs: intelSongs,
        );
"""
        if old in ct:
            ct = ct.replace(old, new, 1)
            print("card intel")
        card.write_text(ct)

# Library badges
lib = ROOT / "lib/screens/library_screen.dart"
if lib.exists():
    lt = lib.read_text()
    if "membershipBadge" not in lt:
        if "mode_shelf_builder.dart" not in lt:
            lt = lt.replace(
                "import 'package:flutter/material.dart';\n",
                "import 'package:flutter/material.dart';\n"
                "import '../modes/providers/mode_provider.dart';\n"
                "import '../providers/intelligence_provider.dart';\n"
                "import '../models/song.dart';\n"
                "import '../services/mode_shelf_builder.dart';\n",
                1,
            )
        if "Consumer2<LibraryProvider, MusicProvider>" in lt:
            lt = lt.replace(
                "Consumer2<LibraryProvider, MusicProvider>",
                "Consumer3<LibraryProvider, MusicProvider, ModeProvider>",
                1,
            )
            lt = lt.replace(
                "builder: (context, library, music, _) {",
                "builder: (context, library, music, modes, _) {",
                1,
            )
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
                                    color: Theme.of(context).colorScheme.tertiary,
                                  ),
                          );
                        },
                      ),
"""
        if old_sub in lt:
            lt = lt.replace(old_sub, new_sub, 1)
            print("library badge")
        lib.write_text(lt)

# DJ soft-gate
mp = ROOT / "lib/providers/music_provider.dart"
mt = mp.read_text()
if "_djHandoffsLive" not in mt:
    needle = "  bool get effectiveCrossfadeEnabled =>\n      _crossfadeEnabled && _modeCrossfadeAllowed;\n"
    if needle in mt:
        mt = mt.replace(
            needle,
            needle
            + "\n  /// DJ handoffs only when mode still allows crossfade.\n"
            "  bool get _djHandoffsLive =>\n      _modeCrossfadeAllowed &&\n      (_djBeatAlignActive || _djTempoMatchActive || _djSfxActive);\n",
            1,
        )
        mt = mt.replace(
            "(_djBeatAlignActive || _djTempoMatchActive || _djSfxActive)",
            "_djHandoffsLive",
        )
        # avoid double-wrap
        mt = mt.replace(
            "_djHandoffsLive && (_djBeatAlignActive || _djTempoMatchActive)",
            "_djHandoffsLive",
        )
        mt = mt.replace(
            "(!_djBeatAlignActive && !_djTempoMatchActive)",
            "(!_djHandoffsLive)",
        )
        mp.write_text(mt)
        print("dj gate")
    else:
        print("WARN dj needle")
else:
    print("dj already")

print("done")
