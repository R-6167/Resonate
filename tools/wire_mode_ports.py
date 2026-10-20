#!/usr/bin/env python3
"""Wire Mode ports into MusicProvider, main.dart, settings on modes_on_dj_v2."""
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]

# --- MusicProvider: mode policy soft gates ---------------------------------
mp = ROOT / "lib/providers/music_provider.dart"
t = mp.read_text()

if "applyModePlaybackPolicy" not in t:
    # Fields near other playback prefs
    anchor = "  bool _shuffleEnabled = false;"
    if anchor not in t:
        raise SystemExit("shuffle field missing")
    t = t.replace(
        anchor,
        anchor
        + "\n  /// Mode soft-gates (from ModeProvider). Defaults preserve legacy behavior.\n"
        + "  bool _modeCrossfadeAllowed = true;\n"
        + "  bool _modeShuffleAllowed = true;\n"
        + "  bool _modePreciseResume = false;\n",
        1,
    )

    # Getters for diagnostics / UI
    g_anchor = "  bool get shuffleEnabled => _shuffleEnabled;"
    if g_anchor not in t:
        raise SystemExit("shuffle getter missing")
    t = t.replace(
        g_anchor,
        g_anchor
        + "\n  bool get modeCrossfadeAllowed => _modeCrossfadeAllowed;\n"
        + "  bool get modeShuffleAllowed => _modeShuffleAllowed;\n"
        + "  bool get modePreciseResume => _modePreciseResume;\n"
        + "  /// User setting AND mode policy both allow crossfade.\n"
        + "  bool get effectiveCrossfadeEnabled =>\n"
        + "      _crossfadeEnabled && _modeCrossfadeAllowed;\n"
        + "  bool get effectiveShuffleEnabled =>\n"
        + "      _shuffleEnabled && _modeShuffleAllowed;\n",
        1,
    )

    # Apply method after setShuffle or near crossfade setters
    method = '''
  /// Called by Modes via [ModePlaybackPort]. Soft gates only — never forces play.
  void applyModePlaybackPolicy({
    required bool crossfadeAllowed,
    required bool shuffleAllowed,
    required bool preciseResume,
  }) {
    final changed = _modeCrossfadeAllowed != crossfadeAllowed ||
        _modeShuffleAllowed != shuffleAllowed ||
        _modePreciseResume != preciseResume;
    _modeCrossfadeAllowed = crossfadeAllowed;
    _modeShuffleAllowed = shuffleAllowed;
    _modePreciseResume = preciseResume;
    if (changed) notifyListeners();
  }
'''
    insert_at = "  Future<void> setCrossfadeEnabled(bool enabled) async"
    if insert_at not in t:
        raise SystemExit("setCrossfadeEnabled missing")
    t = t.replace(insert_at, method + "\n  Future<void> setCrossfadeEnabled(bool enabled) async", 1)

    # Gate canRepeatSelfHandoff
    t = t.replace(
        "  bool get canRepeatSelfHandoff {\n    if (!_crossfadeEnabled) return false;",
        "  bool get canRepeatSelfHandoff {\n    if (!effectiveCrossfadeEnabled) return false;",
        1,
    )

    # Gate common crossfade entry checks: if (!_crossfadeEnabled
    # Only replace patterns that are clearly runtime gates (not prefs load)
    # Replace "if (!_crossfadeEnabled" used as gate with effective
    t = t.replace("if (!_crossfadeEnabled ||", "if (!effectiveCrossfadeEnabled ||")
    t = t.replace("if (!_crossfadeEnabled)", "if (!effectiveCrossfadeEnabled)")
    t = t.replace("if (_crossfadeEnabled &&", "if (effectiveCrossfadeEnabled &&")
    # wantGapless / loopMode style
    t = t.replace("(!_crossfadeEnabled)", "(!effectiveCrossfadeEnabled)")
    t = t.replace("|| _crossfadeEnabled)", "|| effectiveCrossfadeEnabled)")
    t = t.replace("_gaplessSourceActive || _crossfadeEnabled", "_gaplessSourceActive || effectiveCrossfadeEnabled")

    # Shuffle: when building shuffled queues use effectiveShuffleEnabled for behavior
    # Keep setShuffleEnabled storing user pref; gate runtime uses:
    t = t.replace(
        "final nextQueue = _shuffleEnabled && normalized.length > 1",
        "final nextQueue = effectiveShuffleEnabled && normalized.length > 1",
        1,
    )
    t = t.replace(
        "final nextIndex = _shuffleEnabled && normalized.length > 1 ? 0 : selectedIndex;",
        "final nextIndex = effectiveShuffleEnabled && normalized.length > 1 ? 0 : selectedIndex;",
        1,
    )
    t = t.replace(
        "if (_shuffleEnabled && additions.length > 1) additions.shuffle(math.Random());",
        "if (effectiveShuffleEnabled && additions.length > 1) additions.shuffle(math.Random());",
        1,
    )

    # Precise resume: skip restore when mode says not precise
    old_resume = """      if (_resumeSongId == currentSong!.id && _resumePositionMs > 1500) {
        final cap = currentDuration?.inMilliseconds ?? _resumePositionMs;
        final ms = _resumePositionMs.clamp(0, cap).toInt();
"""
    new_resume = """      if (_modePreciseResume &&
          _resumeSongId == currentSong!.id &&
          _resumePositionMs > 1500) {
        final cap = currentDuration?.inMilliseconds ?? _resumePositionMs;
        final ms = _resumePositionMs.clamp(0, cap).toInt();
"""
    if old_resume in t:
        t = t.replace(old_resume, new_resume, 1)
        print("precise resume gated")
    else:
        print("WARN: resume block pattern miss — soft skip")

    mp.write_text(t)
    print("music_provider mode policy wired")
else:
    print("music_provider already has applyModePlaybackPolicy")

# --- main.dart -------------------------------------------------------------
main = ROOT / "lib/main.dart"
m = main.read_text()
if "ModeProvider" not in m:
    # imports
    if "import 'modes/providers/mode_provider.dart';" not in m:
        # after other provider imports
        needle = "import 'providers/music_provider.dart';"
        if needle not in m:
            # try package style
            for cand in [
                "import 'package:resonate/providers/music_provider.dart';",
                "import 'providers/dj_mode_provider.dart';",
            ]:
                if cand in m:
                    needle = cand
                    break
        m = m.replace(
            needle,
            needle
            + "\nimport 'modes/providers/mode_provider.dart';"
            + "\nimport 'modes/integration/resonate_mode_ports.dart';",
            1,
        )

    provider_block = """        ChangeNotifierProvider(
          create: (context) =>
              DjModeProvider(music: context.read<MusicProvider>()),
        ),
"""
    modes_block = """        ChangeNotifierProvider(
          create: (context) =>
              DjModeProvider(music: context.read<MusicProvider>()),
        ),
        // Modes layer: policy only. Ports never force play / reclaim focus.
        ChangeNotifierProvider(
          create: (context) {
            final modes = ModeProvider();
            modes.attachPlayback(
              ResonateModePlaybackPort(context.read<MusicProvider>()),
            );
            modes.attachContext(
              ResonateModeContextPort(context.read<BluetoothProvider>()),
            );
            return modes;
          },
        ),
"""
    if provider_block not in m:
        raise SystemExit("DjModeProvider block not found for ModeProvider insert")
    m = m.replace(provider_block, modes_block, 1)
    main.write_text(m)
    print("main.dart ModeProvider registered")
else:
    print("main.dart already has ModeProvider")

# --- settings_screen.dart --------------------------------------------------
settings = ROOT / "lib/screens/settings_screen.dart"
s = settings.read_text()
if "ModesScreen" not in s:
    if "import '../modes/screens/modes_screen.dart';" not in s:
        s = "import '../modes/screens/modes_screen.dart';\nimport '../modes/integration/resonate_mode_ports.dart';\n" + s
    # Insert Modes item near DJ Mode
    item = "_item(context, 'DJ Mode', 'Optional beat, tempo and harmonic blending'"
    # find first DJ Mode item and insert Modes before Playback section style
    modes_item = (
        "              _item(context, 'Modes', "
        "'Listening context — Driving, Podcast, Running, Work', "
        "Icons.tune_rounded, "
        "ModesScreen(folderPicker: const ResonateModeFolderPickerPort())),\n"
    )
    # Prefer insert after the tip / before first _item with Equalizer or after Playback header
    marker = "              _item(context, 'DJ Mode',"
    if marker in s:
        s = s.replace(marker, modes_item + "              _item(context, 'DJ Mode',", 1)
        settings.write_text(s)
        print("settings Modes entry added")
    else:
        print("WARN: DJ Mode item marker miss")
else:
    print("settings already references ModesScreen")

print("wire_mode_ports done")
