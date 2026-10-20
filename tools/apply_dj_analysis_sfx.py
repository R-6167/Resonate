#!/usr/bin/env python3
"""Finish MP3 analysis enrichment + soft transition SFX."""
from pathlib import Path

# --- estimator: ID3+PCM merge + longer window ---
EST = Path("lib/services/dj_bpm_estimator.dart")
t = EST.read_text()
old_id3 = """      if (head != null && head.isNotEmpty) {
        fromId3 = _parseId3Tbpm(head);
        key = _parseId3Tkey(head);
        if (fromId3 != null) {
          if (key == null) return fromId3;
          return DjBpmEstimate(
            bpm: fromId3.bpm,
            confidence: fromId3.confidence,
            beatOffsetMs: fromId3.beatOffsetMs,
            source: fromId3.source,
            keyRoot: key.keyRoot,
            keyMode: key.keyMode,
            keyConfidence: key.confidence,
          );
        }
      }

      // 3) Native PCM decode for compressed / MediaStore tracks
      final nativePcm = await _estimateFromNativePcm(filePath);
      if (nativePcm != null) {
        if (key != null) {
          return DjBpmEstimate(
            bpm: nativePcm.bpm,
            confidence: nativePcm.confidence,
            beatOffsetMs: nativePcm.beatOffsetMs,
            source: nativePcm.source,
            keyRoot: key.keyRoot,
            keyMode: key.keyMode,
            keyConfidence: key.confidence,
            energy: nativePcm.energy,
            loudness: nativePcm.loudness,
          );
        }
        return nativePcm;
      }
"""
new_id3 = """      if (head != null && head.isNotEmpty) {
        fromId3 = _parseId3Tbpm(head);
        key = _parseId3Tkey(head);
      }

      // 3) Native PCM decode for compressed / MediaStore tracks.
      // Always try PCM so energy / loudness / beatOffset exist even when ID3 has BPM.
      final nativePcm = await _estimateFromNativePcm(filePath);
      if (nativePcm != null) {
        // Prefer tagged BPM when present (higher trust), keep PCM energy/offset.
        if (fromId3 != null) {
          return DjBpmEstimate(
            bpm: fromId3.bpm,
            confidence: math.max(fromId3.confidence, 0.75),
            beatOffsetMs: nativePcm.beatOffsetMs,
            source: 'id3_tbpm+pcm',
            keyRoot: key?.keyRoot,
            keyMode: key?.keyMode,
            keyConfidence: key?.confidence ?? 0.0,
            energy: nativePcm.energy,
            loudness: nativePcm.loudness,
          );
        }
        if (key != null) {
          return DjBpmEstimate(
            bpm: nativePcm.bpm,
            confidence: nativePcm.confidence,
            beatOffsetMs: nativePcm.beatOffsetMs,
            source: nativePcm.source,
            keyRoot: key.keyRoot,
            keyMode: key.keyMode,
            keyConfidence: key.confidence,
            energy: nativePcm.energy,
            loudness: nativePcm.loudness,
          );
        }
        return nativePcm;
      }

      // ID3 BPM only (no PCM) — still better than nothing.
      if (fromId3 != null) {
        return DjBpmEstimate(
          bpm: fromId3.bpm,
          confidence: fromId3.confidence,
          beatOffsetMs: fromId3.beatOffsetMs,
          source: fromId3.source,
          keyRoot: key?.keyRoot,
          keyMode: key?.keyMode,
          keyConfidence: key?.confidence ?? 0.0,
        );
      }
"""
if "id3_tbpm+pcm" in t:
    print("estimator merge already")
else:
    if old_id3 not in t:
        raise SystemExit("id3 block miss")
    t = t.replace(old_id3, new_id3, 1)
    print("estimator merge applied")
if "'maxSeconds': 12.0" in t:
    t = t.replace("'maxSeconds': 12.0", "'maxSeconds': 15.0", 1)
    print("window 15s")
EST.write_text(t)

# --- model analysisVersion 3 ---
MODEL = Path("lib/models/dj_analysis.dart")
md = MODEL.read_text()
if "currentVersion = 3" in md:
    print("model v3 already")
else:
    md = md.replace(
        "/// (v1: native PCM BPM; v2: energy / loudness from same PCM window).\n  static const int currentVersion = 2;",
        "/// (v1: native PCM BPM; v2: energy/loudness; v3: beatOffset + ID3+PCM merge).\n  static const int currentVersion = 3;",
        1,
    )
    MODEL.write_text(md)
    print("model v3")

# --- settings store: transition SFX ---
STORE = Path("lib/services/dj_mode_settings_store.dart")
st = STORE.read_text()
if "transitionSfx" in st:
    print("store sfx already")
else:
    st = st.replace(
        "static const _analyzeIdleKey = 'dj_mode_analyze_idle';",
        "static const _analyzeIdleKey = 'dj_mode_analyze_idle';\n  static const _transitionSfxKey = 'dj_mode_transition_sfx';",
        1,
    )
    st = st + """

  /// Soft reverb glue during DJ crossfade (restored after).
  static Future<bool> transitionSfx() async {
    final p = await SharedPreferences.getInstance();
    return p.getBool(_transitionSfxKey) ?? true;
  }

  static Future<void> setTransitionSfx(bool value) async {
    final p = await SharedPreferences.getInstance();
    await p.setBool(_transitionSfxKey, value);
  }
"""
    STORE.write_text(st)
    print("store sfx")

# --- dj_mode_provider: load/set/push sfx ---
DP = Path("lib/providers/dj_mode_provider.dart")
dp = DP.read_text()
if "_transitionSfx" not in dp:
    dp = dp.replace(
        "  bool _analyzeIdle = false;",
        "  bool _analyzeIdle = false;\n  bool _transitionSfx = true;",
        1,
    )
    # getter near analyzeIdle
    if "bool get analyzeIdle" in dp:
        dp = dp.replace(
            "bool get analyzeIdle", "bool get transitionSfx => _transitionSfx;\n  bool get analyzeIdle", 1
        )
    # load
    if "_analyzeIdle = await DjModeSettingsStore.analyzeIdle" in dp:
        dp = dp.replace(
            "_analyzeIdle = await DjModeSettingsStore.analyzeIdle();",
            "_analyzeIdle = await DjModeSettingsStore.analyzeIdle();\n      _transitionSfx = await DjModeSettingsStore.transitionSfx();",
            1,
        )
    # set method before runIdleScan or after setAnalyzeIdle
    if "Future<void> setAnalyzeIdle" in dp and "setTransitionSfx" not in dp:
        insert = '''
  Future<void> setTransitionSfx(bool value) async {
    _transitionSfx = value;
    notifyListeners();
    await DjModeSettingsStore.setTransitionSfx(value);
    _pushToMusic();
  }
'''
        dp = dp.replace("  Future<void> setAnalyzeIdle", insert + "  Future<void> setAnalyzeIdle", 1)
    # _pushToMusic configureDjMode call
    if "configureDjMode(" in dp and "sfxActive" not in dp:
        # find configureDjMode block and add sfxActive
        old = "music.configureDjMode(\n      beatAlignActive:"
        # more flexible
        import re
        m = re.search(r"music\.configureDjMode\(\s*beatAlignActive:[^;]+;", dp, re.S)
        if m:
            block = m.group(0)
            if "sfxActive" not in block:
                # before closing paren of configureDjMode
                new_block = block.rstrip()
                if new_block.endswith(");"):
                    # insert before last )
                    inner = new_block[:-2]
                    if not inner.rstrip().endswith(","):
                        inner = inner.rstrip() + ","
                    new_block = inner + "\n      sfxActive: _enabled && _transitionSfx,\n    );"
                    dp = dp.replace(block, new_block, 1)
                    print("configure sfx")
    DP.write_text(dp)
    print("provider sfx")
else:
    print("provider sfx already")

# --- settings UI tile ---
UI = Path("lib/screens/dj_mode_settings_screen.dart")
ui = UI.read_text()
if "Transition SFX" not in ui and "transitionSfx" not in ui:
    needle = "title: 'Analyze library when idle',"
    if needle in ui:
        # insert a pref tile before analyze idle
        block = """              _prefTile(
                context,
                enabled: on,
                title: 'Transition SFX',
                subtitle:
                    'Soft reverb glue during DJ crossfades (restored after). Never changes normal play.',
                value: dj.transitionSfx,
                onChanged: on ? dj.setTransitionSfx : null,
              ),
              _prefTile(
                context,
                enabled: on,
                title: 'Analyze library when idle',
"""
        ui = ui.replace(
            """              _prefTile(
                context,
                enabled: on,
                title: 'Analyze library when idle',
""",
            block,
            1,
        )
        UI.write_text(ui)
        print("ui sfx")
    else:
        print("WARN ui needle miss")
else:
    print("ui sfx already")

# --- music_provider: sfxActive + engage/restore ---
MP = Path("lib/providers/music_provider.dart")
m = MP.read_text()
if "_djSfxActive" not in m:
    m = m.replace(
        "  int _djMaxStretchPercent = 12;",
        "  int _djMaxStretchPercent = 12;\n  bool _djSfxActive = false;",
        1,
    )
    print("sfx field")

# configureDjMode signature
if "sfxActive" not in m.split("configureDjMode")[1][:400]:
    old = """  void configureDjMode({
    required bool beatAlignActive,
    bool tempoMatchActive = false,
    int maxStretchPercent = 12,
    DjAnalysisService? analysis,
  }) {
    final wasActive = _djBeatAlignActive || _djTempoMatchActive;
    _djBeatAlignActive = beatAlignActive;
    _djTempoMatchActive = tempoMatchActive;
    _djMaxStretchPercent = maxStretchPercent.clamp(3, 20);
    _djAnalysis = analysis;
"""
    new = """  void configureDjMode({
    required bool beatAlignActive,
    bool tempoMatchActive = false,
    int maxStretchPercent = 12,
    bool sfxActive = false,
    DjAnalysisService? analysis,
  }) {
    final wasActive = _djBeatAlignActive || _djTempoMatchActive;
    _djBeatAlignActive = beatAlignActive;
    _djTempoMatchActive = tempoMatchActive;
    _djMaxStretchPercent = maxStretchPercent.clamp(3, 20);
    _djSfxActive = sfxActive;
    _djAnalysis = analysis;
"""
    if old not in m:
        raise SystemExit("configureDjMode miss")
    m = m.replace(old, new, 1)
    print("configure sfx")

# SFX helpers before _prepareDjHandoff
if "_engageDjTransitionSfx" not in m:
    helpers = '''
  /// Soft transition SFX: mild reverb glue, always restored after crossfade.
  Future<void> _engageDjTransitionSfx() async {
    if (!_djSfxActive) return;
    try {
      await AudioEffectsBridge.setReverb(0.22);
      await ResonateDiagnostics.record('dj_transition_sfx', {
        'action': 'engage',
        'reverb': 0.22,
      });
    } catch (e) {
      debugPrint('DJ transition SFX engage: $e');
    }
  }

  Future<void> _restoreDjTransitionSfx() async {
    if (!_djSfxActive) return;
    try {
      final prefs = await SharedPreferences.getInstance();
      final effectsEnabled = prefs.getBool('effects_enabled') ?? true;
      final reverb = prefs.getDouble('reverb') ?? 0.0;
      await AudioEffectsBridge.setReverb(effectsEnabled ? reverb : 0.0);
      await ResonateDiagnostics.record('dj_transition_sfx', {
        'action': 'restore',
        'reverb': effectsEnabled ? reverb : 0.0,
      });
    } catch (e) {
      debugPrint('DJ transition SFX restore: $e');
    }
  }

'''
    anchor = "  /// Step 2–3: optional beat seek + tempo stretch for the incoming handoff.\n  Future<void> _prepareDjHandoff"
    if anchor not in m:
        raise SystemExit("sfx helper anchor miss")
    m = m.replace(anchor, helpers + anchor, 1)
    print("sfx helpers")

# Engage after prepare, restore after fade completes / on abort paths
if "_engageDjTransitionSfx()" not in m:
    old = """      await _prepareDjHandoff(
        outgoing: outgoing,
        incoming: incoming,
        outgoingSong: outgoingSong,
        incomingSong: nextSong,
      );
      // Fire-and-poll play on B"""
    new = """      await _prepareDjHandoff(
        outgoing: outgoing,
        incoming: incoming,
        outgoingSong: outgoingSong,
        incomingSong: nextSong,
      );
      await _engageDjTransitionSfx();
      // Fire-and-poll play on B"""
    if old not in m:
        raise SystemExit("engage anchor miss")
    m = m.replace(old, new, 1)
    print("engage wired")

# Restore before successful return paths - after fade loop ends, before commit
# Look for Guarantee silence on outgoing
if "_restoreDjTransitionSfx()" not in m:
    old = "      // Guarantee silence on outgoing before pause/stop — never cut from a\n      // still-audible level (the \"sudden volume loss\" symptom)."
    new = "      await _restoreDjTransitionSfx();\n      // Guarantee silence on outgoing before pause/stop — never cut from a\n      // still-audible level (the \"sudden volume loss\" symptom)."
    if old not in m:
        print("WARN restore primary miss")
    else:
        m = m.replace(old, new, 1)
        print("restore primary")

    # Also restore on early aborts that return false after prepare
    for marker in [
        "await _clearDjStretchSpeeds(outgoing: outgoing, incoming: incoming);\n            return false;",
    ]:
        # only first few after engage - safer to wrap finally
        pass

    # Add finally-style restore near _crossfadeInProgress = false at end of try
    # Search for end of _performTrueCrossfade finally
    if "_crossfadeInProgress = false" in m and m.count("_restoreDjTransitionSfx") < 2:
        # inject into a common abort path
        abort = """            try { await incoming.stop(); } catch (_) {}
            try { await outgoing.setVolume(base); } catch (_) {}
            await _clearDjStretchSpeeds(outgoing: outgoing, incoming: incoming);
            return false;"""
        abort_new = """            try { await incoming.stop(); } catch (_) {}
            try { await outgoing.setVolume(base); } catch (_) {}
            await _clearDjStretchSpeeds(outgoing: outgoing, incoming: incoming);
            await _restoreDjTransitionSfx();
            return false;"""
        if abort in m:
            m = m.replace(abort, abort_new)  # all
            print("restore aborts")

MP.write_text(m)
print("music_provider done")
print("ALL DONE")
