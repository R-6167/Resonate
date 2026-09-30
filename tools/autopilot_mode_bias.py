#!/usr/bin/env python3
"""Wire Autopilot content bias to Mode PlaybackPolicy."""
from pathlib import Path
import re

ROOT = Path(__file__).resolve().parents[1]


def patch_mode_provider() -> None:
    path = ROOT / "lib/providers/mode_provider.dart"
    t = path.read_text()
    if "isAcceptableForAutopilot" in t:
        print("mode: bias helpers already present")
        return

    old = """  /// Soft content filter for AutoNext / Intelligence (never blocks explicit play).
  bool shouldPreferSong(Song song) {
    final type = mediaTypeFor(song);
    final p = policy;
    if (!p.allowsMediaType(type)) return false;
    return p.prefersMediaType(type);
  }

  /// Whether crossfade is allowed under the active mode policy.
  bool get crossfadeAllowed => policy.crossfadeAllowed;
}
"""
    new = """  /// Soft content filter for AutoNext / Intelligence (never blocks explicit play).
  /// Rejects avoided types; requires preferred match when the mode has a prefer set.
  bool shouldPreferSong(Song song) {
    final type = mediaTypeFor(song);
    final p = policy;
    if (!p.allowsMediaType(type)) return false;
    return p.prefersMediaType(type);
  }

  /// Autopilot may pick this track (not on the avoided list).
  /// Explicit user play is never blocked by this.
  bool isAcceptableForAutopilot(Song song) {
    return policy.allowsMediaType(mediaTypeFor(song));
  }

  /// Mode actively prefers this content kind (empty prefer set = no bias).
  bool isPreferredContent(Song song) {
    return policy.prefersMediaType(mediaTypeFor(song));
  }

  /// Sort key: preferred first, then acceptable, avoided last (-1).
  int contentBiasScore(Song song) {
    final type = mediaTypeFor(song);
    final p = policy;
    if (!p.allowsMediaType(type)) return -1;
    if (p.preferredMediaTypes.isEmpty) return 1;
    if (p.preferredMediaTypes.contains(type)) return 2;
    return 0; // allowed but not preferred (e.g. unknown while Running)
  }

  /// Whether crossfade is allowed under the active mode policy.
  bool get crossfadeAllowed => policy.crossfadeAllowed;
}
"""
    if old not in t:
        raise SystemExit("mode: shouldPreferSong block miss")
    path.write_text(t.replace(old, new, 1))
    print("mode: bias helpers added")


def patch_autopilot() -> None:
    path = ROOT / "lib/providers/autopilot_controller.dart"
    t = path.read_text()

    # Ensure mode_provider import
    if "mode_provider.dart" not in t:
        if "import 'music_provider.dart';" in t:
            t = t.replace(
                "import 'music_provider.dart';",
                "import 'music_provider.dart';\nimport 'mode_provider.dart';",
                1,
            )
        else:
            t = "import 'mode_provider.dart';\n" + t

    # Ensure modes field + ctor
    if "this.modes" not in t:
        t = re.sub(
            r"AutopilotController\(\{required this\.music,\s*required this\.intelligence\}\)",
            "AutopilotController({required this.music, required this.intelligence, this.modes})",
            t,
            count=1,
        )
    if "final ModeProvider? modes" not in t and "ModeProvider? modes" not in t:
        if "final MusicProvider music;" in t:
            t = t.replace(
                "final MusicProvider music;",
                "final MusicProvider music;\n  final ModeProvider? modes;",
                1,
            )
        elif "final MusicProvider music" in t:
            t = t.replace(
                "final MusicProvider music",
                "final MusicProvider music;\n  final ModeProvider? modes",
                1,
            )

    # Listen to mode changes
    if "modes?.addListener" not in t and "_onModeChanged" not in t:
        t = t.replace(
            "    music.addListener(_onPlaybackChanged);\n"
            "    intelligence.addListener(_onIntelligenceChanged);\n",
            "    music.addListener(_onPlaybackChanged);\n"
            "    intelligence.addListener(_onIntelligenceChanged);\n"
            "    modes?.addListener(_onModeChanged);\n",
            1,
        )
        t = t.replace(
            "  void _onPlaybackChanged() => _scheduleEvaluate();\n"
            "  void _onIntelligenceChanged() => _scheduleEvaluate();\n",
            "  void _onPlaybackChanged() => _scheduleEvaluate();\n"
            "  void _onIntelligenceChanged() => _scheduleEvaluate();\n"
            "  void _onModeChanged() => _scheduleEvaluate();\n",
            1,
        )
        t = t.replace(
            "    music.removeListener(_onPlaybackChanged);\n"
            "    intelligence.removeListener(_onIntelligenceChanged);\n",
            "    music.removeListener(_onPlaybackChanged);\n"
            "    intelligence.removeListener(_onIntelligenceChanged);\n"
            "    modes?.removeListener(_onModeChanged);\n",
            1,
        )

    # Replace candidate selection block with ranked bias
    old_pick = """    // Prefer the highest-confidence recommendation that is not the current song
    final candidates = intelligence.recommendations
        .where((r) => r.song.id != music.currentSong?.id && r.confidence >= threshold)
        .toList();

    Song? nextSong;
    IntelligenceRecommendation? recommendation;

    if (candidates.isNotEmpty) {
      recommendation = candidates.first;
      nextSong = recommendation.song;
      // Mode policy: soft content bias (never blocks explicit user play).
      if (modes != null && !modes!.shouldPreferSong(nextSong)) {
        nextSong = null;
      }
    } else if (intelligence.isAutopilotGraduated) {
"""

    new_pick = """    // Rank recommendations by mode content bias, then keep confidence order.
    // Avoided types are dropped; preferred types sort first. Never blocks explicit user play.
    final rawCandidates = intelligence.recommendations
        .where((r) => r.song.id != music.currentSong?.id && r.confidence >= threshold)
        .toList();
    final candidates = _rankByModeBias(rawCandidates);

    Song? nextSong;
    IntelligenceRecommendation? recommendation;

    if (candidates.isNotEmpty) {
      recommendation = candidates.first;
      nextSong = recommendation.song;
    } else if (intelligence.isAutopilotGraduated) {
"""

    if old_pick in t:
        t = t.replace(old_pick, new_pick, 1)
        print("autopilot: ranked candidate pick")
    elif "_rankByModeBias" in t:
        print("autopilot: rank already present")
    else:
        # try without the partial bias lines
        old2 = """    // Prefer the highest-confidence recommendation that is not the current song
    final candidates = intelligence.recommendations
        .where((r) => r.song.id != music.currentSong?.id && r.confidence >= threshold)
        .toList();

    Song? nextSong;
    IntelligenceRecommendation? recommendation;

    if (candidates.isNotEmpty) {
      recommendation = candidates.first;
      nextSong = recommendation.song;
    } else if (intelligence.isAutopilotGraduated) {
"""
        if old2 in t:
            t = t.replace(old2, new_pick, 1)
            print("autopilot: ranked candidate pick (v2)")
        else:
            print("autopilot: candidate block miss")

    # Graduated path: filter queue next / top by mode
    if "// Mode bias on graduated queue next" not in t:
        old_g = """      if (music.queueIndex < music.queue.length - 1) {
        nextSong = music.queue[music.queueIndex + 1];
      } else if (_consentGranted) {
        await _ensurePredictedQueue(threshold);
        final top = intelligence.anticipatedNext?.song;
        if (top != null && top.id != music.currentSong?.id) {
          await music.enqueueSongs([top]);
          nextSong = top;
        }
      }
"""
        new_g = """      if (music.queueIndex < music.queue.length - 1) {
        final queued = music.queue[music.queueIndex + 1];
        if (_acceptable(queued)) {
          nextSong = queued;
        }
      } else if (_consentGranted) {
        await _ensurePredictedQueue(threshold);
        final top = intelligence.anticipatedNext?.song;
        if (top != null && top.id != music.currentSong?.id && _acceptable(top)) {
          await music.enqueueSongs([top]);
          nextSong = top;
        }
      }
"""
        if old_g in t:
            t = t.replace(old_g, new_g, 1)
            print("autopilot: graduated path mode filter")

    # Crossfade respects mode policy
    if "modes?.crossfadeAllowed" not in t and "modeAllowsXf" not in t:
        t = t.replace(
            "    final useCrossfade = await IntelligenceSettingsStore.autopilotCrossfade();\n",
            "    final autopilotWantsXf = await IntelligenceSettingsStore.autopilotCrossfade();\n"
            "    final useCrossfade = autopilotWantsXf && (modes?.crossfadeAllowed ?? true);\n",
            1,
        )
        print("autopilot: mode crossfade gate")

    # Filter chooseSequence results
    if "_filterModeSongs" not in t and "candidates.where(_acceptable)" not in t:
        old_enq = """      if (candidates.isNotEmpty) {
        final added = await music.enqueueSongs(candidates);
"""
        new_enq = """      final modeFiltered = candidates.where(_acceptable).toList();
      if (modeFiltered.isNotEmpty) {
        final added = await music.enqueueSongs(modeFiltered);
"""
        if old_enq in t:
            t = t.replace(old_enq, new_enq, 1)
            # fix diagnostics candidates reference
            t = t.replace(
                "'candidates': candidates.map((song) => song.id).toList(),",
                "'candidates': modeFiltered.map((song) => song.id).toList(),",
                1,
            )
            t = t.replace(
                "songId: candidates.first.id,",
                "songId: modeFiltered.first.id,",
                1,
            )
            print("autopilot: queue fill mode filter")

    # Helper methods before dispose
    if "List<IntelligenceRecommendation> _rankByModeBias" not in t:
        helpers = """
  bool _acceptable(Song song) {
    final m = modes;
    if (m == null) return true;
    return m.isAcceptableForAutopilot(song);
  }

  /// Drop avoided types; stable-sort preferred ahead of neutral (confidence order kept).
  List<IntelligenceRecommendation> _rankByModeBias(
    List<IntelligenceRecommendation> input,
  ) {
    final m = modes;
    if (m == null) return input;
    final kept = input.where((r) => m.isAcceptableForAutopilot(r.song)).toList();
    kept.sort((a, b) {
      final sa = m.contentBiasScore(a.song);
      final sb = m.contentBiasScore(b.song);
      if (sa != sb) return sb.compareTo(sa); // higher score first
      return 0; // preserve relative confidence order within same score
    });
    return kept;
  }

"""
        if "  @override\n  void dispose()" in t:
            t = t.replace("  @override\n  void dispose()", helpers + "  @override\n  void dispose()", 1)
            print("autopilot: helpers added")
        else:
            t = t + "\n" + helpers
            print("autopilot: helpers appended")

    # Diagnostics: include mode id on transition
    if "'resonateMode'" not in t:
        t = t.replace(
            "'toSongId': nextSong.id,",
            "'toSongId': nextSong.id,\n"
            "      'resonateMode': modes?.mode.id ?? 'unknown',",
            1,
        )

    path.write_text(t)
    print("autopilot: content bias applied")


def patch_main() -> None:
    path = ROOT / "lib/main.dart"
    t = path.read_text()

    # Move ModeProvider before Autopilot and pass modes:
    if "modes: context.read<ModeProvider>()" in t:
        print("main: modes already passed to Autopilot")
        return

    # Extract ModeProvider block
    mode_block = None
    # current patterns
    patterns = [
        """        ChangeNotifierProvider(
          create: (context) {
            final modes = ModeProvider();
            modes.attachMusic(context.read<MusicProvider>());
            return modes;
          },
        ),
""",
        "        ChangeNotifierProvider(create: (_) => ModeProvider()),\n",
    ]
    for p in patterns:
        if p in t:
            mode_block = p
            t = t.replace(p, "", 1)
            break

    if mode_block is None:
        print("main: ModeProvider block not found")
        path.write_text(t)
        return

    # Prefer the attachMusic version
    mode_block = """        ChangeNotifierProvider(
          create: (context) {
            final modes = ModeProvider();
            modes.attachMusic(context.read<MusicProvider>());
            return modes;
          },
        ),
"""

    # Insert before AutopilotController
    auto = """        ChangeNotifierProvider(
          create: (context) => AutopilotController(
            music: context.read<MusicProvider>(),
            intelligence: context.read<IntelligenceProvider>(),
          ),
        ),
"""
    auto_new = """        ChangeNotifierProvider(
          create: (context) {
            final modes = ModeProvider();
            modes.attachMusic(context.read<MusicProvider>());
            return modes;
          },
        ),
        ChangeNotifierProvider(
          create: (context) => AutopilotController(
            music: context.read<MusicProvider>(),
            intelligence: context.read<IntelligenceProvider>(),
            modes: context.read<ModeProvider>(),
          ),
        ),
"""
    if auto in t:
        t = t.replace(auto, auto_new, 1)
        print("main: ModeProvider before Autopilot + modes wired")
    else:
        # softer match
        if "AutopilotController(" in t and "modes:" not in t:
            t = t.replace(
                "            intelligence: context.read<IntelligenceProvider>(),\n"
                "          ),\n",
                "            intelligence: context.read<IntelligenceProvider>(),\n"
                "            modes: context.read<ModeProvider>(),\n"
                "          ),\n",
                1,
            )
            # still need ModeProvider before it
            if "ModeProvider()" not in t:
                t = t.replace(
                    "        ChangeNotifierProvider(\n"
                    "          create: (context) => AutopilotController(",
                    mode_block
                    + "        ChangeNotifierProvider(\n"
                    "          create: (context) => AutopilotController(",
                    1,
                )
            print("main: modes wired (fallback)")
        else:
            print("main: Autopilot block miss")

    # Deduplicate ModeProvider if two remain
    count = t.count("ModeProvider()")
    if count > 1:
        # remove later duplicate attachMusic block
        second = t.find("final modes = ModeProvider();", t.find("final modes = ModeProvider();") + 1)
        if second > 0:
            # find ChangeNotifierProvider containing it
            start = t.rfind("ChangeNotifierProvider(", 0, second)
            end = t.find("),\n", second) + 3
            if start > 0 and end > start:
                t = t[:start] + t[end:]
                print("main: removed duplicate ModeProvider")

    path.write_text(t)


def main() -> None:
    patch_mode_provider()
    patch_autopilot()
    patch_main()
    print("autopilot mode bias done")


if __name__ == "__main__":
    main()
