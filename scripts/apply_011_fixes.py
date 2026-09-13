from pathlib import Path


def replace(path, old, new):
    p = Path(path)
    text = p.read_text()
    if old not in text:
        raise SystemExit(f"Expected text not found in {path}: {old[:140]!r}")
    p.write_text(text.replace(old, new, 1))


# MusicProvider: startup audio effects, effect parity across the A/B engines,
# and one serialized lane for automatic completion transitions.
replace(
    "lib/providers/music_provider.dart",
    "import '../services/library_visibility_store.dart';",
    "import '../services/library_visibility_store.dart';\nimport '../services/audio_effects_bridge.dart';",
)
replace(
    "lib/providers/music_provider.dart",
    "      await _syncSystemVolume();\n      if (!const ['linear', 'ease_in', 'ease_out', 'ease_in_out'].contains(_crossfadeFadeType)) _crossfadeFadeType = 'linear';",
    "      await _syncSystemVolume();\n      await syncSavedAudioEffects();\n      if (!const ['linear', 'ease_in', 'ease_out', 'ease_in_out'].contains(_crossfadeFadeType)) _crossfadeFadeType = 'linear';",
)

p = Path("lib/providers/music_provider.dart")
text = p.read_text()
marker = "  Future<void> _configureAudioSession() async {"
helper = r'''  Future<void> syncSavedAudioEffects() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final equalizerEnabled = prefs.getBool('equalizer_enabled') ?? true;
      final effectsEnabled = prefs.getBool('effects_enabled') ?? true;
      final bassBoost = prefs.getDouble('bassBoost') ?? 0.0;
      final virtualizer = prefs.getDouble('virtualizer') ?? 0.0;
      final reverb = prefs.getDouble('reverb') ?? 0.0;
      final loudness = prefs.getDouble('loudness') ?? 0.0;
      for (final pair in <(AndroidEqualizer, AndroidLoudnessEnhancer)>[
        (_equalizerA, _loudnessA),
        (_equalizerB, _loudnessB),
      ]) {
        final eq = pair.$1;
        final loud = pair.$2;
        try {
          final parameters = await eq.parameters;
          for (final band in parameters.bands) {
            final saved = prefs.getDouble('eq_band_${band.index}');
            if (saved != null) {
              await band.setGain(saved.clamp(parameters.minDecibels, parameters.maxDecibels).toDouble());
            }
          }
          await eq.setEnabled(equalizerEnabled);
        } catch (_) {}
        try {
          await loud.setTargetGain(effectsEnabled ? loudness * 600.0 : 0.0);
          await loud.setEnabled(effectsEnabled && loudness > 0);
        } catch (_) {}
      }
      final sessionId = audioPlayer.androidAudioSessionId;
      if (sessionId != null && sessionId > 0) {
        await AudioEffectsBridge.attachToSession(sessionId);
        await AudioEffectsBridge.setBassBoost(effectsEnabled ? bassBoost : 0.0);
        await AudioEffectsBridge.setVirtualizer(effectsEnabled ? virtualizer : 0.0);
        await AudioEffectsBridge.setReverb(effectsEnabled ? reverb : 0.0);
      }
    } catch (e) {
      debugPrint('Saved audio effects sync failed: $e');
    }
  }

'''
if marker not in text:
    raise SystemExit("MusicProvider configure marker missing")
p.write_text(text.replace(marker, helper + marker, 1))

replace(
    "lib/providers/music_provider.dart",
    "  Future<void> _enableEffects(AudioPlayer player, AndroidEqualizer eq, AndroidLoudnessEnhancer loud) async { try { await eq.setEnabled(true); } catch (e) { debugPrint('Equalizer unavailable: $e'); } try { await loud.setEnabled(true); } catch (e) { debugPrint('Loudness enhancer unavailable: $e'); } }",
    r'''  Future<void> _enableEffects(AudioPlayer player, AndroidEqualizer eq, AndroidLoudnessEnhancer loud) async {
    try { await eq.setEnabled(true); } catch (e) { debugPrint('Equalizer unavailable: $e'); }
    try { await loud.setEnabled(true); } catch (e) { debugPrint('Loudness enhancer unavailable: $e'); }
    try {
      final sessionId = player.androidAudioSessionId;
      if (sessionId != null && sessionId > 0) {
        final prefs = await SharedPreferences.getInstance();
        final enabled = prefs.getBool('effects_enabled') ?? true;
        await AudioEffectsBridge.attachToSession(sessionId);
        await AudioEffectsBridge.setBassBoost(enabled ? (prefs.getDouble('bassBoost') ?? 0.0) : 0.0);
        await AudioEffectsBridge.setVirtualizer(enabled ? (prefs.getDouble('virtualizer') ?? 0.0) : 0.0);
        await AudioEffectsBridge.setReverb(enabled ? (prefs.getDouble('reverb') ?? 0.0) : 0.0);
      }
      await syncSavedAudioEffects();
    } catch (e) { debugPrint('Audio effects activation failed: $e'); }
  }''',
)
replace(
    "lib/providers/music_provider.dart",
    "        } else if (!_completionAdvanceInProgress) {\n          unawaited(_advanceAfterCompletion());\n        }",
    "        } else if (!_completionAdvanceInProgress) {\n          unawaited(_advanceAfterCompletion(completedSongId));\n        }",
)
replace(
    "lib/providers/music_provider.dart",
    "  Future<void> _advanceAfterCompletion() async {\n    if (_completionAdvanceInProgress) return;\n    _completionAdvanceInProgress = true;",
    "  Future<void> _advanceAfterCompletion(String completedSongId) {\n    if (_completionAdvanceInProgress) return Future<void>.value();\n    return _serializePlayback(\n      () => _advanceAfterCompletionInternal(completedSongId),\n      command: 'completion_advance',\n      source: 'automatic_transition',\n    );\n  }\n\n  Future<void> _advanceAfterCompletionInternal(String completedSongId) async {\n    if (_completionAdvanceInProgress || currentSong?.id != completedSongId) return;\n    _completionAdvanceInProgress = true;",
)

# Autopilot: acceptance can arrive after the current song has already completed.
replace(
    "lib/providers/autopilot_controller.dart",
    "    if (!_consentLoaded || !intelligence.isAutopilot || !music.isPlaying || music.currentSong == null) return;\n\n    final automaticQueue = await IntelligenceSettingsStore.automaticQueue();",
    "    if (!_consentLoaded || !intelligence.isAutopilot || music.currentSong == null) return;\n    if (!music.isPlaying && !forceTransition) return;\n\n    final automaticQueue = await IntelligenceSettingsStore.automaticQueue();",
)

# Library counters describe the visible, folder-scoped library rather than the retained DB.
replace(
    "lib/providers/library_provider.dart",
    "  Future<void> loadStatistics() async { try { _statistics = await _db.getStatistics(); notifyListeners(); } catch (e) { debugPrint('Error loading statistics: $e'); } }",
    """  Future<void> loadStatistics() async {
    try {
      final raw = await _db.getStatistics();
      _statistics = Map<String, dynamic>.from(raw);
      _statistics['totalSongs'] = _allSongs.length;
      _statistics['favoriteCount'] = _favoriteSongs.length;
      notifyListeners();
    } catch (e) { debugPrint('Error loading statistics: $e'); }
  }""",
)
