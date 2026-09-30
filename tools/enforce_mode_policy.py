#!/usr/bin/env python3
"""Enforce Mode PlaybackPolicy in MusicProvider + ModeProvider + Autopilot."""
from pathlib import Path
import re

ROOT = Path(__file__).resolve().parents[1]


def patch_music() -> None:
    path = ROOT / "lib/providers/music_provider.dart"
    t = path.read_text()
    if "applyModePlaybackPolicy" in t:
        print("music: policy already present")
        return

    # Add policy flags near crossfade fields
    old = "  bool _crossfadeEnabled = false;\n"
    new = (
        "  bool _crossfadeEnabled = false;\n"
        "  /// Mode policy gate — user crossfade pref stays in _crossfadeEnabled.\n"
        "  bool _policyCrossfadeAllowed = true;\n"
        "  bool _policyShuffleAllowed = true;\n"
    )
    if old not in t:
        raise SystemExit("music: crossfade field miss")
    t = t.replace(old, new, 1)

    # Public getters: effective behavior
    t = t.replace(
        "  bool get shuffleEnabled => _shuffleEnabled;\n",
        "  bool get shuffleEnabled => _shuffleEnabled && _policyShuffleAllowed;\n"
        "  bool get shuffleUserPreference => _shuffleEnabled;\n",
        1,
    )
    t = t.replace(
        "  bool get crossfadeEnabled => _crossfadeEnabled;\n",
        "  /// Effective crossfade (user pref AND mode policy).\n"
        "  bool get crossfadeEnabled => _crossfadeEnabled && _policyCrossfadeAllowed;\n"
        "  bool get crossfadeUserPreference => _crossfadeEnabled;\n"
        "  bool get modeAllowsCrossfade => _policyCrossfadeAllowed;\n"
        "  bool get modeAllowsShuffle => _policyShuffleAllowed;\n",
        1,
    )

    # applyModePlaybackPolicy method before setCrossfadeEnabled
    anchor = "  Future<void> setCrossfadeEnabled(bool enabled) async"
    method = (
        "  /// Called by ModeProvider when the active mode's PlaybackPolicy changes.\n"
        "  /// Does not overwrite user preferences — only gates runtime behavior.\n"
        "  void applyModePlaybackPolicy({\n"
        "    required bool crossfadeAllowed,\n"
        "    required bool shuffleAllowed,\n"
        "  }) {\n"
        "    final changed = _policyCrossfadeAllowed != crossfadeAllowed ||\n"
        "        _policyShuffleAllowed != shuffleAllowed;\n"
        "    _policyCrossfadeAllowed = crossfadeAllowed;\n"
        "    _policyShuffleAllowed = shuffleAllowed;\n"
        "    if (changed) notifyListeners();\n"
        "  }\n"
        "\n"
        "  Future<void> setCrossfadeEnabled(bool enabled) async"
    )
    if anchor not in t:
        raise SystemExit("music: setCrossfadeEnabled anchor miss")
    t = t.replace(anchor, method, 1)

    # Runtime gates: use effective getter (crossfadeEnabled) instead of field
    # Careful: do not change assignments or prefs keys
    replacements = [
        ("if (!_crossfadeEnabled) return false;", "if (!crossfadeEnabled) return false;"),
        ("if (index == null || _crossfadeEnabled || _crossfadeInProgress) return;",
         "if (index == null || crossfadeEnabled || _crossfadeInProgress) return;"),
        ("if (!_crossfadeEnabled || !audioPlayer.playing) return;",
         "if (!crossfadeEnabled || !audioPlayer.playing) return;"),
        ("if (!_crossfadeEnabled ||\n",
         "if (!crossfadeEnabled ||\n"),
        ("if (!_crossfadeEnabled || _crossfadePreloadInFlight || !canCrossfadeNext) return;",
         "if (!crossfadeEnabled || _crossfadePreloadInFlight || !canCrossfadeNext) return;"),
        ("final graceMs = _crossfadeEnabled", "final graceMs = crossfadeEnabled"),
        ("final loopMode = (!_crossfadeEnabled)", "final loopMode = (!crossfadeEnabled)"),
        ("final wantGapless = !_crossfadeEnabled && nextQueue.length > 1;",
         "final wantGapless = !crossfadeEnabled && nextQueue.length > 1;"),
        ("if (!_gaplessSourceActive || _crossfadeEnabled) return false;",
         "if (!_gaplessSourceActive || crossfadeEnabled) return false;"),
    ]
    for a, b in replacements:
        if a in t:
            t = t.replace(a, b)
            print(f"music gate: {a[:40]}...")
        else:
            print(f"music gate miss: {a[:50]}")

    # Shuffle runtime: use getter (already effective)
    t = t.replace(
        "final nextQueue = _shuffleEnabled && normalized.length > 1",
        "final nextQueue = shuffleEnabled && normalized.length > 1",
    )
    t = t.replace(
        "final nextIndex = _shuffleEnabled && normalized.length > 1 ? 0 : selectedIndex;",
        "final nextIndex = shuffleEnabled && normalized.length > 1 ? 0 : selectedIndex;",
    )
    t = t.replace(
        "if (_shuffleEnabled && additions.length > 1) additions.shuffle(math.Random());",
        "if (shuffleEnabled && additions.length > 1) additions.shuffle(math.Random());",
    )

    path.write_text(t)
    print("music: policy enforcement applied")


def patch_mode_provider() -> None:
    path = ROOT / "lib/providers/mode_provider.dart"
    t = path.read_text()
    if "applyModePlaybackPolicy" in t and "MusicProvider" in t:
        print("mode: engine bind already present")
        # still ensure push on setMode
        pass

    if "import 'music_provider.dart'" not in t:
        t = t.replace(
            "import '../models/song.dart';\n",
            "import '../models/song.dart';\nimport 'music_provider.dart';\n",
            1,
        )

    if "MusicProvider? _music" not in t:
        t = t.replace(
            "  final MediaClassifier _classifier = MediaClassifier.instance;\n"
            "  final MediaClassificationStore _store = MediaClassificationStore();\n",
            "  final MediaClassifier _classifier = MediaClassifier.instance;\n"
            "  final MediaClassificationStore _store = MediaClassificationStore();\n"
            "  MusicProvider? _music;\n",
            1,
        )

    if "void attachMusic" not in t:
        # after constructor
        old = "  ModeProvider() {\n    _init();\n  }\n"
        new = (
            "  ModeProvider() {\n"
            "    _init();\n"
            "  }\n"
            "\n"
            "  /// Bind the single playback engine so policy can gate crossfade/shuffle.\n"
            "  void attachMusic(MusicProvider music) {\n"
            "    _music = music;\n"
            "    _pushPolicyToEngine();\n"
            "  }\n"
            "\n"
            "  void _pushPolicyToEngine() {\n"
            "    final p = policy;\n"
            "    _music?.applyModePlaybackPolicy(\n"
            "      crossfadeAllowed: p.crossfadeAllowed,\n"
            "      shuffleAllowed: p.shuffleAllowed,\n"
            "    );\n"
            "  }\n"
        )
        if old not in t:
            raise SystemExit("mode: constructor miss")
        t = t.replace(old, new, 1)

    # After init notify, push policy
    if "_pushPolicyToEngine();" not in t.split("_ready = true")[1][:200]:
        t = t.replace(
            "    _ready = true;\n    notifyListeners();\n",
            "    _ready = true;\n    _pushPolicyToEngine();\n    notifyListeners();\n",
            1,
        )

    # setMode pushes policy
    if "_pushPolicyToEngine();" not in t.split("Future<void> setMode")[1][:400]:
        t = t.replace(
            "    _mode = mode;\n    notifyListeners();\n",
            "    _mode = mode;\n    _pushPolicyToEngine();\n    notifyListeners();\n",
            1,
        )

    path.write_text(t)
    print("mode: engine bind + push on setMode")


def patch_main() -> None:
    path = ROOT / "lib/main.dart"
    t = path.read_text()
    old = "        ChangeNotifierProvider(create: (_) => ModeProvider()),\n"
    new = (
        "        ChangeNotifierProvider(\n"
        "          create: (context) {\n"
        "            final modes = ModeProvider();\n"
        "            modes.attachMusic(context.read<MusicProvider>());\n"
        "            return modes;\n"
        "          },\n"
        "        ),\n"
    )
    if "modes.attachMusic" in t:
        print("main: attachMusic already wired")
        return
    if old not in t:
        # try alternate formatting
        if "ModeProvider()" in t and "attachMusic" not in t:
            t2 = re.sub(
                r"ChangeNotifierProvider\(create: \(_\) => ModeProvider\(\)\),",
                "ChangeNotifierProvider(\n"
                "          create: (context) {\n"
                "            final modes = ModeProvider();\n"
                "            modes.attachMusic(context.read<MusicProvider>());\n"
                "            return modes;\n"
                "          },\n"
                "        ),",
                t,
                count=1,
            )
            if t2 == t:
                raise SystemExit("main: ModeProvider create miss")
            t = t2
            path.write_text(t)
            print("main: attachMusic wired (regex)")
            return
        raise SystemExit("main: ModeProvider line miss")
    t = t.replace(old, new, 1)
    path.write_text(t)
    print("main: attachMusic wired")


def patch_crossfade_ui() -> None:
    path = ROOT / "lib/providers/crossfade_provider.dart"
    t = path.read_text()
    if "effectivelyEnabled" in t:
        print("crossfade: effectivelyEnabled already")
        return
    # Add effective getter after isEnabled field
    t = t.replace(
        "  bool isEnabled = false;\n",
        "  bool isEnabled = false;\n"
        "  /// User pref AND mode policy (podcast/audiobook force off).\n"
        "  bool get effectivelyEnabled => isEnabled && music.modeAllowsCrossfade;\n",
        1,
    )
    path.write_text(t)
    print("crossfade: effectivelyEnabled getter")

    # Soft hint on crossfade screen if present
    screen = ROOT / "lib/screens/crossfade_screen.dart"
    if screen.exists():
        s = screen.read_text()
        if "modeAllowsCrossfade" in s or "Modes block" in s:
            print("crossfade screen: already mode-aware")
            return
        if "resonate_glass.dart" not in s and "package:flutter/material.dart" in s:
            pass
        # Insert a banner after first Consumer or body - soft touch
        if "CrossfadeProvider" in s and "modeAllowsCrossfade" not in s:
            # Add import mode_provider if missing
            if "mode_provider.dart" not in s:
                s = s.replace(
                    "import 'package:provider/provider.dart';",
                    "import 'package:provider/provider.dart';\nimport '../providers/mode_provider.dart';",
                    1,
                )
            path.write_text  # no-op keep screen optional
            # Optional: skip screen for now to avoid layout risk
            print("crossfade screen: left unchanged (engine gate is enough)")


def patch_autopilot() -> None:
    path = ROOT / "lib/providers/autopilot_controller.dart"
    t = path.read_text()
    if "shouldPreferSong" in t:
        print("autopilot: mode filter already")
        return

    if "mode_provider.dart" not in t:
        # add import
        if "import 'music_provider.dart';" in t:
            t = t.replace(
                "import 'music_provider.dart';",
                "import 'music_provider.dart';\nimport 'mode_provider.dart';",
                1,
            )
        elif "import '../providers/music_provider.dart';" in t:
            t = t.replace(
                "import '../providers/music_provider.dart';",
                "import '../providers/music_provider.dart';\nimport '../providers/mode_provider.dart';",
                1,
            )

    # Find constructor / fields for MusicProvider and IntelligenceProvider
    # Add optional ModeProvider via constructor if pattern matches
    if "final ModeProvider" not in t and "ModeProvider?" not in t:
        # AutopilotController(music:, intelligence:)
        m = re.search(
            r"AutopilotController\(\{\s*required this\.music,\s*required this\.intelligence,?\s*\}\)",
            t,
        )
        if m:
            t = t.replace(
                m.group(0),
                "AutopilotController({required this.music, required this.intelligence, this.modes})",
                1,
            )
            # add field near music field
            if "final MusicProvider music;" in t:
                t = t.replace(
                    "final MusicProvider music;",
                    "final MusicProvider music;\n  final ModeProvider? modes;",
                    1,
                )
            print("autopilot: ModeProvider optional ctor")
        else:
            print("autopilot: ctor pattern miss — soft filter via Provider not available; skip bind")
            path.write_text(t)
            return

    # Filter recommendation song preference before enqueue
    # Look for recommendation.song usage
    if "modes?.shouldPreferSong" not in t:
        # After nextSong = recommendation.song
        if "nextSong = recommendation.song;" in t:
            t = t.replace(
                "nextSong = recommendation.song;",
                "nextSong = recommendation.song;\n"
                "      // Mode policy: soft content bias (never blocks explicit user play).\n"
                "      if (modes != null && !modes!.shouldPreferSong(nextSong)) {\n"
                "        nextSong = null;\n"
                "      }",
                1,
            )
            print("autopilot: shouldPreferSong on recommendation")
        else:
            print("autopilot: recommendation.song assign miss")

    path.write_text(t)

    # Wire main AutopilotController create
    main = ROOT / "lib/main.dart"
    mt = main.read_text()
    if "AutopilotController(" in mt and "modes:" not in mt.split("AutopilotController")[1][:300]:
        old = (
            "          create: (context) => AutopilotController(\n"
            "            music: context.read<MusicProvider>(),\n"
            "            intelligence: context.read<IntelligenceProvider>(),\n"
            "          ),\n"
        )
        # ModeProvider is created AFTER Autopilot in current main — need reorder or lazy read
        # Autopilot is before ModeProvider currently. Reorder ModeProvider before Autopilot OR pass null and re-bind.
        # Safer: leave modes null at create; ModeProvider doesn't need to reverse-bind autopilot for v1.
        print("autopilot main: ModeProvider is after Autopilot — content filter optional until reorder")
    main.write_text(mt)


def reorder_main_mode_before_autopilot() -> None:
    """Optional: place ModeProvider early so Autopilot can read it."""
    path = ROOT / "lib/main.dart"
    t = path.read_text()
    if "modes: context.read<ModeProvider>" in t:
        print("main: autopilot already has modes")
        return

    # If ModeProvider block exists later, inject modes into Autopilot create
    # Autopilot is created before ModeProvider — ProxyProvider pattern is heavy.
    # Simpler: keep autopilot filter when modes != null; ModeProvider can call
    # a future attach on Autopilot if needed. For v1 engine crossfade/shuffle is enough.
    print("main: skip autopilot reorder (crossfade/shuffle are primary)")


def main() -> None:
    patch_music()
    patch_mode_provider()
    patch_main()
    patch_crossfade_ui()
    patch_autopilot()
    reorder_main_mode_before_autopilot()
    print("enforce mode policy done")


if __name__ == "__main__":
    main()
