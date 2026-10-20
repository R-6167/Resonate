#!/usr/bin/env python3
"""Minor polish: glass BT/viz/companion, drop intel placeholders, wave default, EQ+audio."""
from pathlib import Path
import re

ROOT = Path(__file__).resolve().parents[1]

PLACEHOLDER_SECTIONS = (
    "Suggestions",
    "Automatic queue",
    "Exploration",
    "Explanations",
    "Learning",
    "Session Intelligence",
)


def patch_settings() -> None:
    path = ROOT / "lib/screens/settings_screen.dart"
    lines = path.read_text().splitlines(keepends=True)
    out = []
    removed = []
    for line in lines:
        drop = False
        for section in PLACEHOLDER_SECTIONS:
            if f"IntelligenceDetailScreen(section: '{section}')" in line:
                drop = True
                removed.append(section)
                break
        if not drop:
            out.append(line)
    path.write_text("".join(out))
    print("settings removed:", removed or "none")

    t = path.read_text()
    # Glass Bluetooth scaffold
    idx = t.find("class BluetoothSettingsScreen")
    if idx >= 0:
        chunk = t[idx : idx + 1200]
        if "ResonateGlassScaffold" not in chunk:
            old = (
                "      return Scaffold(\n"
                "        appBar: AppBar(title: const Text('Bluetooth & media controls')),\n"
                "        body: Consumer<BluetoothProvider>(\n"
            )
            new = (
                "      return ResonateGlassScaffold(\n"
                "        title: const Text('Bluetooth & media controls'),\n"
                "        body: Consumer<BluetoothProvider>(\n"
            )
            if old in t:
                t = t.replace(old, new, 1)
                print("BT screen → glass scaffold")
            else:
                print("BT scaffold pattern miss")
        path.write_text(t)


def patch_viz() -> None:
    path = ROOT / "lib/providers/audio_visualization_provider.dart"
    t = path.read_text()
    t = t.replace("visualizationType = 'bars'", "visualizationType = 'wave'")
    t = t.replace("?? 'bars'", "?? 'wave'")
    path.write_text(t)
    print("viz default → wave")

    path = ROOT / "lib/screens/audio_visualization_settings_screen.dart"
    t = path.read_text()
    if "resonate_glass.dart" not in t:
        t = t.replace(
            "import 'package:flutter/material.dart';",
            "import 'package:flutter/material.dart';\nimport '../ui/resonate_glass.dart';",
            1,
        )
    if "ResonateGlassScaffold" not in t:
        t = t.replace(
            "return Scaffold(appBar: AppBar(title: const Text('Visualization')), body:",
            "return ResonateGlassScaffold(title: const Text('Visualization'), body:",
            1,
        )
        t = t.replace(
            "const Padding(padding: EdgeInsets.all(16), child: Card(",
            "const Padding(padding: EdgeInsets.all(16), child: ResonateGlassCard(",
            1,
        )
        print("viz screen → glass")
    path.write_text(t)


def patch_takeover() -> None:
    path = ROOT / "lib/widgets/autopilot_takeover_card.dart"
    t = path.read_text()
    if "resonate_glass.dart" not in t:
        t = t.replace(
            "import 'package:flutter/material.dart';",
            "import 'package:flutter/material.dart';\nimport '../ui/resonate_glass.dart';",
            1,
        )
    old = (
        "                child: Material(\n"
        "                  elevation: 7,\n"
        "                  shadowColor: scheme.shadow.withOpacity(.28),\n"
        "                  borderRadius: BorderRadius.circular(20),\n"
        "                  color: scheme.primaryContainer,\n"
        "                  child: Padding(\n"
        "                    padding: const EdgeInsets.fromLTRB(14, 12, 8, 10),\n"
    )
    new = (
        "                child: ResonateGlassCard(\n"
        "                  borderRadius: 20,\n"
        "                  padding: EdgeInsets.zero,\n"
        "                  child: Padding(\n"
        "                    padding: const EdgeInsets.fromLTRB(14, 12, 8, 10),\n"
    )
    if old in t:
        t = t.replace(old, new, 1)
        print("takeover pending → glass")
    # Generic Material elevation shells → glass
    t2, n = re.subn(
        r"Material\(\s*elevation:\s*[^,]+,\s*shadowColor:[^,]+,\s*borderRadius:\s*BorderRadius\.circular\((\d+)\),\s*color:[^,]+,\s*child:",
        r"ResonateGlassCard(borderRadius: \1, padding: EdgeInsets.zero, child:",
        t,
        count=5,
    )
    if n:
        t = t2
        print(f"takeover: glassified {n} Material cards")
    path.write_text(t)


def patch_eq() -> None:
    path = ROOT / "lib/providers/equalizer_provider.dart"
    t = path.read_text()
    if "Re-assert saved preset" not in t:
        marker = (
            "      // Digital preamp only at startup (player volume scale). Hardware EQ\n"
            "      // bind waits until playback has been running for a moment.\n"
            "      await _applyPreamp();\n"
            "      notifyListeners();"
        )
        insert = (
            "      // Re-assert saved preset onto studio bands (Custom keeps restored prefs).\n"
            "      if (preset != 'Custom') {\n"
            "        final match = allPresets.where((p) => p.name == preset);\n"
            "        if (match.isNotEmpty) {\n"
            "          _applyStudioGains(match.first.gains);\n"
            "          for (final b in studioBands) {\n"
            "            bands[b.label] = b.gainDb;\n"
            "          }\n"
            "        }\n"
            "      }\n"
            "      // Digital preamp only at startup (player volume scale). Hardware EQ\n"
            "      // bind waits until playback has been running for a moment.\n"
            "      await _applyPreamp();\n"
            "      notifyListeners();"
        )
        if marker in t:
            t = t.replace(marker, insert, 1)
            print("EQ: re-assert preset on init")
        else:
            print("EQ: init marker miss")

    if "Re-apply studio curve after hardware is live" not in t:
        old_bind = (
            "      await _loadHardwareBands();\n"
            "      await _androidEqualizer?.setEnabled(isEnabled);\n"
            "      await _pushToHardware();\n"
            "      await _applyPreamp();\n"
            "      notifyListeners();\n"
        )
        new_bind = (
            "      await _loadHardwareBands();\n"
            "      await _androidEqualizer?.setEnabled(isEnabled);\n"
            "      // Re-apply studio curve after hardware is live so preset survives app restart.\n"
            "      if (preset != 'Custom') {\n"
            "        final match = allPresets.where((p) => p.name == preset);\n"
            "        if (match.isNotEmpty) {\n"
            "          _applyStudioGains(match.first.gains);\n"
            "        }\n"
            "      }\n"
            "      await _pushToHardware();\n"
            "      await _applyPreamp();\n"
            "      try {\n"
            "        final prefs = await SharedPreferences.getInstance();\n"
            "        await prefs.setBool('equalizer_enabled', isEnabled);\n"
            "        await prefs.setString('equalizer_preset', preset);\n"
            "      } catch (_) {}\n"
            "      notifyListeners();\n"
        )
        if old_bind in t:
            t = t.replace(old_bind, new_bind, 1)
            print("EQ: re-apply on hardware bind")
        else:
            print("EQ: bind pattern miss")
    path.write_text(t)


def patch_music_ensure() -> None:
    path = ROOT / "lib/providers/music_provider.dart"
    t = path.read_text()
    if "ensureAudiblePlayback" in t:
        print("music ensureAudible already present")
        return
    anchor = (
        "  /// Claim media focus before any intentional play. Safe to call often.\n"
        "  Future<void> _claimAudioFocus"
    )
    method = (
        "  /// Public: re-claim focus and restore volume if playback went silent while UI moved.\n"
        "  Future<void> ensureAudiblePlayback() async {\n"
        "    try {\n"
        "      if (!_userWantsPlaying && !audioPlayer.playing) return;\n"
        "      await _claimAudioFocus(reason: 'ensure_audible');\n"
        "      final vol = volume.clamp(0.05, 1.0);\n"
        "      if (audioPlayer.volume < vol * 0.85) {\n"
        "        await audioPlayer.setVolume(vol);\n"
        "      }\n"
        "      if (_userWantsPlaying && !audioPlayer.playing) {\n"
        "        await audioPlayer.play();\n"
        "      }\n"
        "    } catch (e) {\n"
        "      debugPrint('ensureAudiblePlayback: $e');\n"
        "    }\n"
        "  }\n"
        "\n"
        "  /// Claim media focus before any intentional play. Safe to call often.\n"
        "  Future<void> _claimAudioFocus"
    )
    if anchor in t:
        t = t.replace(anchor, method, 1)
        path.write_text(t)
        print("music: added ensureAudiblePlayback")
    else:
        print("music: claimAudioFocus anchor miss")


def patch_player_audio() -> None:
    path = ROOT / "lib/screens/player_screen.dart"
    t = path.read_text()
    if "_keepAudioAlive" in t:
        print("player audio keep already present")
        return
    old = (
        "class _PlayerScreenState extends State<PlayerScreen> {\n"
        "  double? _dragPosition;\n"
        "  bool _swipeTutorialChecked = false;\n"
    )
    new = (
        "class _PlayerScreenState extends State<PlayerScreen> with WidgetsBindingObserver {\n"
        "  double? _dragPosition;\n"
        "  bool _swipeTutorialChecked = false;\n"
        "\n"
        "  @override\n"
        "  void initState() {\n"
        "    super.initState();\n"
        "    WidgetsBinding.instance.addObserver(this);\n"
        "  }\n"
        "\n"
        "  @override\n"
        "  void dispose() {\n"
        "    WidgetsBinding.instance.removeObserver(this);\n"
        "    // Leaving the player must not silence active playback.\n"
        "    _keepAudioAlive();\n"
        "    super.dispose();\n"
        "  }\n"
        "\n"
        "  @override\n"
        "  void didChangeAppLifecycleState(AppLifecycleState state) {\n"
        "    if (state == AppLifecycleState.resumed) {\n"
        "      _keepAudioAlive();\n"
        "    }\n"
        "  }\n"
        "\n"
        "  void _keepAudioAlive() {\n"
        "    try {\n"
        "      final music = context.read<MusicProvider>();\n"
        "      if (music.isPlaying || music.currentSong != null) {\n"
        "        unawaited(music.ensureAudiblePlayback());\n"
        "      }\n"
        "    } catch (_) {}\n"
        "  }\n"
    )
    if old not in t:
        print("player state pattern miss")
        return
    t = t.replace(old, new, 1)
    path.write_text(t)
    print("player: keep audio alive on leave/resume")


def main() -> None:
    patch_settings()
    patch_viz()
    patch_takeover()
    patch_eq()
    patch_music_ensure()
    patch_player_audio()
    print("minor polish batch done")


if __name__ == "__main__":
    main()
