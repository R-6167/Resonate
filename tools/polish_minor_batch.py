#!/usr/bin/env python3
"""Minor polish batch: glass BT/viz/companion, remove intel placeholders,
wave default viz, EQ re-apply on bind, keep audio when leaving player."""
from pathlib import Path
import re

ROOT = Path(__file__).resolve().parents[1]


def patch_settings() -> None:
    path = ROOT / "lib/screens/settings_screen.dart"
    t = path.read_text()
    # Remove placeholder Intelligence detail rows (real controls live in Advanced)
    for section, icon in [
        ("Suggestions", "Icons.lightbulb_outline_rounded"),
        ("Automatic queue", "Icons.playlist_add_rounded"),
        ("Exploration", "Icons.explore_outlined"),
        ("Explanations", "Icons.question_mark_rounded"),
        ("Learning", "Icons.insights_rounded"),
        ("Session Intelligence", "Icons.timeline_rounded"),
    ]:
        # Match _item(... IntelligenceDetailScreen(section: '...')),
        pat = re.compile(
            r"\s*_item\(context,\s*'"
            + re.escape(section)
            + r"',\s*'[^']*',\s*[^,]+,\s*const IntelligenceDetailScreen\(section:\s*'"
            + re.escape(section)
            + r"'\)\),?\n",
        )
        t2, n = pat.subn("", t)
        if n:
            t = t2
            print(f"settings: removed {section}")
        else:
            # looser match
            pat2 = re.compile(
                r".*IntelligenceDetailScreen\(section:\s*'"
                + re.escape(section)
                + r"'\).*
"
            )
            t2, n = pat2.subn("", t)
            if n:
                t = t2
                print(f"settings: removed line {section}")
            else:
                print(f"settings: {section} not found (ok)")

    # Glass BluetoothSettingsScreen scaffold
    if "class BluetoothSettingsScreen" in t and "ResonateGlassScaffold" not in t[t.find("class BluetoothSettingsScreen"):t.find("class BluetoothSettingsScreen")+800]:
        old = """      return Scaffold(
        appBar: AppBar(title: const Text('Bluetooth & media controls')),
        body: Consumer<BluetoothProvider>(
"""
        new = """      return ResonateGlassScaffold(
        title: const Text('Bluetooth & media controls'),
        body: Consumer<BluetoothProvider>(
"""
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
    # reset() should default to wave
    t = t.replace(
        "visualizationType = 'bars'; sensitivity",
        "visualizationType = 'wave'; sensitivity",
    )
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
        t = t.replace("const Padding(padding: EdgeInsets.all(16), child: Card(",
                      "const Padding(padding: EdgeInsets.all(16), child: ResonateGlassCard(", 1)
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
    # Replace Material elevation pending card with glass
    old = """                child: Material(
                  elevation: 7,
                  shadowColor: scheme.shadow.withOpacity(.28),
                  borderRadius: BorderRadius.circular(20),
                  color: scheme.primaryContainer,
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(14, 12, 8, 10),
"""
    new = """                child: ResonateGlassCard(
                  borderRadius: 20,
                  padding: EdgeInsets.zero,
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(14, 12, 8, 10),
"""
    if old in t:
        t = t.replace(old, new, 1)
        print("takeover pending → glass")
    # Also replace other Material elevation cards if present
    t2 = re.sub(
        r"Material\(\s*elevation:\s*[^,]+,\s*shadowColor:[^,]+,\s*borderRadius:\s*BorderRadius\.circular\((\d+)\),\s*color:[^,]+,\s*child:",
        r"ResonateGlassCard(borderRadius: \1, padding: EdgeInsets.zero, child:",
        t,
        count=3,
    )
    if t2 != t:
        t = t2
        print("takeover: replaced more Material cards")
    path.write_text(t)


def patch_eq() -> None:
    path = ROOT / "lib/providers/equalizer_provider.dart"
    t = path.read_text()
    # After init load, always re-apply saved preset curve so it sticks across restarts
    marker = "      // Digital preamp only at startup (player volume scale). Hardware EQ\n      // bind waits until playback has been running for a moment.\n      await _applyPreamp();\n      notifyListeners();"
    insert = """      // Re-assert saved preset onto studio bands (Custom keeps restored prefs).
      if (preset != 'Custom') {
        final match = allPresets.where((p) => p.name == preset);
        if (match.isNotEmpty) {
          _applyStudioGains(match.first.gains);
          for (final b in studioBands) {
            bands[b.label] = b.gainDb;
          }
        }
      }
      // Digital preamp only at startup (player volume scale). Hardware EQ
      // bind waits until playback has been running for a moment.
      await _applyPreamp();
      notifyListeners();"""
    if "Re-assert saved preset" not in t and marker in t:
        t = t.replace(marker, insert, 1)
        print("EQ: re-assert preset on init")
    elif "Re-assert saved preset" in t:
        print("EQ: re-assert already present")
    else:
        print("EQ: init marker miss")

    # After hardware bind, push again
    old_bind = """      await _loadHardwareBands();
      await _androidEqualizer?.setEnabled(isEnabled);
      await _pushToHardware();
      await _applyPreamp();
      notifyListeners();
"""
    new_bind = """      await _loadHardwareBands();
      await _androidEqualizer?.setEnabled(isEnabled);
      // Re-apply studio curve after hardware is live so preset survives app restart.
      if (preset != 'Custom') {
        final match = allPresets.where((p) => p.name == preset);
        if (match.isNotEmpty) {
          _applyStudioGains(match.first.gains);
        }
      }
      await _pushToHardware();
      await _applyPreamp();
      try {
        final prefs = await SharedPreferences.getInstance();
        await prefs.setBool('equalizer_enabled', isEnabled);
        await prefs.setString('equalizer_preset', preset);
      } catch (_) {}
      notifyListeners();
"""
    if "Re-apply studio curve after hardware is live" not in t and old_bind in t:
        t = t.replace(old_bind, new_bind, 1)
        print("EQ: re-apply on hardware bind")
    path.write_text(t)


def patch_player_audio() -> None:
    path = ROOT / "lib/screens/player_screen.dart"
    t = path.read_text()
    if "_keepAudioAlive" in t:
        print("player audio keep already present")
        return
    # Add dispose + route-aware keep-alive
    old = """class _PlayerScreenState extends State<PlayerScreen> {
  double? _dragPosition;
  bool _swipeTutorialChecked = false;
"""
    new = """class _PlayerScreenState extends State<PlayerScreen> with WidgetsBindingObserver {
  double? _dragPosition;
  bool _swipeTutorialChecked = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    // Leaving the player must not silence active playback.
    _keepAudioAlive();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _keepAudioAlive();
    }
  }

  void _keepAudioAlive() {
    try {
      final music = context.read<MusicProvider>();
      if (music.isPlaying || music.currentSong != null) {
        // Re-claim focus + unstick silent volume if watchdog lagged.
        unawaited(music.ensureAudiblePlayback());
      }
    } catch (_) {}
  }
"""
    if old not in t:
        print("player state pattern miss")
        return
    t = t.replace(old, new, 1)
    path.write_text(t)
    print("player: keep audio alive on leave/resume")


def patch_music_ensure() -> None:
    path = ROOT / "lib/providers/music_provider.dart"
    t = path.read_text()
    if "ensureAudiblePlayback" in t:
        print("music ensureAudible already present")
        return
    # Insert public method near silent watchdog / claimAudioFocus
    anchor = "  /// Claim media focus before any intentional play. Safe to call often.\n  Future<void> _claimAudioFocus"
    method = """  /// Public: re-claim focus and restore volume if playback went silent while UI moved.
  Future<void> ensureAudiblePlayback() async {
    try {
      if (!_userWantsPlaying && !audioPlayer.playing) return;
      await _claimAudioFocus(reason: 'ensure_audible');
      final vol = volume.clamp(0.05, 1.0);
      if (audioPlayer.volume < vol * 0.85) {
        await audioPlayer.setVolume(vol);
      }
      if (_userWantsPlaying && !audioPlayer.playing) {
        await audioPlayer.play();
      }
    } catch (e) {
      debugPrint('ensureAudiblePlayback: $e');
    }
  }

  /// Claim media focus before any intentional play. Safe to call often.
  Future<void> _claimAudioFocus"""
    if anchor in t:
        t = t.replace(anchor, method, 1)
        path.write_text(t)
        print("music: added ensureAudiblePlayback")
    else:
        print("music: claimAudioFocus anchor miss")


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
