#!/usr/bin/env python3
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]

# --- AutopilotController: optional ModeProvider bias -------------------------
ap = ROOT / "lib/providers/autopilot_controller.dart"
t = ap.read_text()
if "ModeProvider?" not in t and "modeBias" not in t:
    if "import 'music_provider.dart';" in t and "modes/providers/mode_provider" not in t:
        t = t.replace(
            "import 'music_provider.dart';\n",
            "import 'music_provider.dart';\n"
            "import '../modes/providers/mode_provider.dart';\n"
            "import '../modes/models/mode_media_item.dart';\n",
            1,
        )
    t = t.replace(
        "  final MusicProvider music;\n  final IntelligenceProvider intelligence;\n",
        "  final MusicProvider music;\n  final IntelligenceProvider intelligence;\n  final ModeProvider? modes;\n",
        1,
    )
    t = t.replace(
        "  AutopilotController({required this.music, required this.intelligence}) {",
        "  AutopilotController({\n    required this.music,\n    required this.intelligence,\n    this.modes,\n  }) {",
        1,
    )

    helper = '''
  ModeMediaItem _asModeItem(Song song) => ModeMediaItem(
        id: song.id,
        filePath: song.filePath,
        title: song.title,
        album: song.album,
        artist: song.artist,
      );

  /// Soft mode bias: drop disallowed types, prefer preferred types. Never forces play.
  List<Song> _applyModeBias(List<Song> songs) {
    final m = modes;
    if (m == null || songs.isEmpty) return songs;
    final allowed = <Song>[];
    for (final s in songs) {
      final item = _asModeItem(s);
      if (m.isAcceptableForAutopilot(item)) allowed.add(s);
    }
    if (allowed.isEmpty) return songs; // fail open so Autopilot is not starved
    allowed.sort((a, b) {
      final sb = m.contentBiasScore(_asModeItem(b));
      final sa = m.contentBiasScore(_asModeItem(a));
      return sb.compareTo(sa);
    });
    return allowed;
  }
'''
    # insert before _ensurePredictedQueue
    if "_applyModeBias" not in t:
        t = t.replace(
            "  Future<void> _ensurePredictedQueue(double threshold) async {",
            helper + "\n  Future<void> _ensurePredictedQueue(double threshold) async {",
            1,
        )

    # Bias recommendation list in transition path
    old_cand = """    final candidates = intelligence.recommendations
        .where((r) => r.song.id != music.currentSong?.id)
        .toList();
"""
    # be flexible
    import re
    pat = re.compile(
        r"final candidates = intelligence\.recommendations\n"
        r"\s*\.where\(\(r\) => r\.song\.id != music\.currentSong\?\.id\)\n"
        r"\s*\.toList\(\);",
    )
    m = pat.search(t)
    if m:
        t = t[: m.start()] + (
            "final candidates = _applyModeBias(\n"
            "      intelligence.recommendations\n"
            "          .where((r) => r.song.id != music.currentSong?.id)\n"
            "          .map((r) => r.song)\n"
            "          .toList(),\n"
            "    );\n"
            "    // Rebuild recommendation pointer from biased song list\n"
            "    final recById = {\n"
            "      for (final r in intelligence.recommendations) r.song.id: r,\n"
            "    };\n"
        ) + t[m.end() :]
        # Fix next song selection that expected IntelligenceRecommendation list
        t = t.replace(
            "    IntelligenceRecommendation? recommendation;\n\n    if (candidates.isNotEmpty) {\n      recommendation = candidates.first;\n      nextSong = recommendation.song;\n",
            "    IntelligenceRecommendation? recommendation;\n\n    if (candidates.isNotEmpty) {\n      nextSong = candidates.first;\n      recommendation = recById[nextSong.id];\n",
            1,
        )
        print("transition candidates biased")
    else:
        print("WARN: transition candidates pattern miss")

    # Bias enqueue sequence
    t = t.replace(
        "      if (candidates.isNotEmpty) {\n        final added = await music.enqueueSongs(candidates);",
        "      final biased = _applyModeBias(candidates);\n"
        "      if (biased.isNotEmpty) {\n        final added = await music.enqueueSongs(biased);",
        1,
    )
    # fix diagnostics that referenced candidates
    t = t.replace(
        "'candidates': candidates.map((song) => song.id).toList(),",
        "'candidates': biased.map((song) => song.id).toList(),",
        1,
    )
    t = t.replace(
        "songId: candidates.first.id,",
        "songId: biased.first.id,",
        1,
    )

    ap.write_text(t)
    print("autopilot mode bias wired")
else:
    print("autopilot already has modes")

# --- main.dart: ModeProvider before Autopilot + pass modes ------------------
main = ROOT / "lib/main.dart"
m = main.read_text()

# Ensure Autopilot construction includes modes:
if "AutopilotController(" in m and "modes:" not in m.split("AutopilotController(")[1][:200]:
    m = m.replace(
        """        ChangeNotifierProvider(
          create: (context) => AutopilotController(
            music: context.read<MusicProvider>(),
            intelligence: context.read<IntelligenceProvider>(),
          ),
        ),
""",
        """        ChangeNotifierProvider(
          create: (context) => AutopilotController(
            music: context.read<MusicProvider>(),
            intelligence: context.read<IntelligenceProvider>(),
            modes: context.read<ModeProvider>(),
          ),
        ),
""",
        1,
    )
    print("autopilot ctor modes arg")

# Move ModeProvider block to just after BluetoothProvider if currently after DjMode
if "ResonateModePlaybackPort" in m:
    # Extract ModeProvider provider block
    start = m.find("        // Modes: policy only.")
    if start < 0:
        start = m.find("        // Modes layer:")
    if start < 0:
        # try without comment
        start = m.find(
            "        ChangeNotifierProvider(\n"
            "          create: (context) {\n"
            "            final modes = ModeProvider();"
        )
    if start >= 0:
        # find end of this provider — next "        ChangeNotifierProvider" after attachContext block closing
        end_marker = "            return modes;\n          },\n        ),\n"
        end = m.find(end_marker, start)
        if end > 0:
            end = end + len(end_marker)
            block = m[start:end]
            m_wo = m[:start] + m[end:]
            # Insert after BluetoothProvider create line
            bt = "        ChangeNotifierProvider(create: (_) => BluetoothProvider()),\n"
            if bt in m_wo and block not in m_wo[m_wo.find(bt) : m_wo.find(bt) + 800]:
                m_wo = m_wo.replace(bt, bt + block, 1)
                m = m_wo
                print("ModeProvider moved after Bluetooth")
            else:
                print("ModeProvider order already ok or bt miss")
                m = m  # keep
        else:
            print("ModeProvider end marker miss")
    else:
        print("ModeProvider block start miss")

main.write_text(m)
print("main updated")
